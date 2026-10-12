import Foundation
import Network
import Security
import XCTest
@testable import SkylitCore

struct TestIdentity {
    let identity: SecIdentity
    let fingerprint: String

    static func make() throws -> TestIdentity {
        let tool = "/usr/bin/openssl"
        guard FileManager.default.isExecutableFile(atPath: tool) else { throw XCTSkip("openssl is needed to make a test certificate") }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("skylit-tls-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let key = folder.appendingPathComponent("key.pem").path
        let certificate = folder.appendingPathComponent("cert.pem").path
        let bundle = folder.appendingPathComponent("identity.p12")
        let passphrase = UUID().uuidString
        for arguments in [
            ["ecparam", "-name", "prime256v1", "-genkey", "-noout", "-out", key],
            ["req", "-x509", "-new", "-key", key, "-sha256", "-days", "3650", "-subj", "/CN=Skylit", "-out", certificate],
            ["pkcs12", "-export", "-inkey", key, "-in", certificate, "-out", bundle.path, "-passout", "pass:\(passphrase)"],
        ] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: tool)
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw XCTSkip("openssl could not make a test certificate") }
        }
        guard #available(macOS 15.0, iOS 18.0, *) else { throw XCTSkip("Importing a test identity in memory needs a newer system") }
        var imported: CFArray?
        let options: [String: Any] = [kSecImportExportPassphrase as String: passphrase, kSecImportToMemoryOnly as String: true]
        guard SecPKCS12Import(try Data(contentsOf: bundle) as CFData, options as CFDictionary, &imported) == errSecSuccess,
              let first = (imported as? [[String: Any]])?.first, let value = first[kSecImportItemIdentity as String] else {
            throw XCTSkip("This Mac could not import a test identity")
        }
        let identity = value as! SecIdentity
        var leaf: SecCertificate?
        SecIdentityCopyCertificate(identity, &leaf)
        let der = SecCertificateCopyData(try XCTUnwrap(leaf)) as Data
        return TestIdentity(identity: identity, fingerprint: Pin.fingerprint(ofCertificate: der))
    }
}

final class TLSTestServer: @unchecked Sendable {
    let fingerprint: String
    private(set) var port: UInt16 = 0
    private let listener: NWListener
    private let lock = NSLock()
    private var received: [Data] = []
    private var accepted = 0
    private let respond: @Sendable (String) -> Data

    var url: URL { URL(string: "https://127.0.0.1:\(port)")! }
    var connections: Int { lock.withLock { accepted } }
    var applicationBytes: Int { lock.withLock { received.reduce(0) { $0 + $1.count } } }
    var requests: [String] { lock.withLock { received.map { String(decoding: $0, as: UTF8.self) } } }

    static func json(_ status: String, _ body: String, extra: String = "") -> Data {
        Data("HTTP/1.1 \(status)\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\n\(extra)Connection: close\r\n\r\n\(body)".utf8)
    }

    init(_ identity: TestIdentity, respond: @escaping @Sendable (String) -> Data) async throws {
        fingerprint = identity.fingerprint
        self.respond = respond
        let tls = NWProtocolTLS.Options()
        sec_protocol_options_set_local_identity(tls.securityProtocolOptions, try XCTUnwrap(sec_identity_create(identity.identity)))
        sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
        sec_protocol_options_set_max_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
        let parameters = NWParameters(tls: tls)
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            let index = self.lock.withLock {
                self.accepted += 1
                self.received.append(Data())
                return self.received.count - 1
            }
            connection.start(queue: .global())
            self.read(connection, index)
        }
        port = try await withCheckedThrowingContinuation { ready in
            listener.stateUpdateHandler = { [listener] state in
                switch state {
                case .ready:
                    listener.stateUpdateHandler = nil
                    ready.resume(returning: listener.port?.rawValue ?? 0)
                case .failed(let error):
                    listener.stateUpdateHandler = nil
                    ready.resume(throwing: error)
                default:
                    break
                }
            }
            listener.start(queue: .global())
        }
    }

    deinit {
        listener.cancel()
    }

    private func read(_ connection: NWConnection, _ index: Int) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            let buffer: Data = self.lock.withLock {
                if let data { self.received[index].append(data) }
                return self.received[index]
            }
            if let reply = self.reply(to: buffer) {
                connection.send(content: reply, completion: .contentProcessed { _ in connection.cancel() })
            } else if isComplete || error != nil {
                connection.cancel()
            } else {
                self.read(connection, index)
            }
        }
    }

    private func reply(to buffer: Data) -> Data? {
        guard let headEnd = buffer.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let head = String(decoding: buffer[..<headEnd.lowerBound], as: UTF8.self)
        let length = head.split(separator: "\r\n").first { $0.lowercased().hasPrefix("content-length:") }
            .flatMap { Int($0.split(separator: ":")[1].trimmingCharacters(in: .whitespaces)) } ?? 0
        return buffer.count - headEnd.upperBound >= length ? respond(head) : nil
    }
}
