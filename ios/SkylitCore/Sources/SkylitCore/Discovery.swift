import Foundation
import Network

public struct DiscoveredFrame: Equatable, Identifiable, Sendable {
    public let frameId: String
    public let name: String

    public var id: String { frameId }

    public init(frameId: String, name: String) {
        self.frameId = frameId
        self.name = name
    }

    public static func unique(_ frames: [DiscoveredFrame]) -> [DiscoveredFrame] {
        var seen = Set<String>()
        return frames.filter { seen.insert($0.frameId).inserted }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

public enum BrowseEvent: Equatable, Sendable {
    case services([String])
    case permissionDenied
    case failed(String)
}

public protocol FrameBrowsing: Sendable {
    func events() -> AsyncStream<BrowseEvent>
    func resolve(service: String) async throws -> URL
}

public enum FrameAddress {
    public static let defaultPort = 8765

    public static func url(host: String, port: Int) -> URL? {
        var components = URLComponents()
        components.scheme = "http"
        components.host = host.split(separator: "%").first.map(String.init) ?? host
        components.port = port
        return components.url
    }

    public static func parse(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(" ") else { return nil }
        guard let components = URLComponents(string: trimmed.contains("://") ? trimmed : "http://\(trimmed)"),
              components.scheme == "http", components.user == nil,
              let host = components.host, !host.isEmpty else { return nil }
        let port = components.port ?? defaultPort
        guard (1...65535).contains(port) else { return nil }
        return url(host: host, port: port)
    }
}

public final class BonjourFrameBrowser: FrameBrowsing, @unchecked Sendable {
    public static let serviceType = "_skylit._tcp"
    private static let policyDenied: Int32 = -65570

    private let lock = NSLock()
    private var endpoints: [String: NWEndpoint] = [:]

    public init() {}

    public func events() -> AsyncStream<BrowseEvent> {
        AsyncStream { continuation in
            let browser = NWBrowser(for: .bonjour(type: Self.serviceType, domain: nil), using: .tcp)
            browser.stateUpdateHandler = { state in
                switch state {
                case .waiting(let error), .failed(let error):
                    if case .dns(let code) = error, code == Self.policyDenied {
                        continuation.yield(.permissionDenied)
                    } else {
                        continuation.yield(.failed(error.localizedDescription))
                    }
                default:
                    break
                }
            }
            browser.browseResultsChangedHandler = { [weak self] results, _ in
                var found: [String: NWEndpoint] = [:]
                for result in results {
                    guard case .service(let name, _, _, _) = result.endpoint else { continue }
                    found[name] = result.endpoint
                }
                self?.lock.withLock { self?.endpoints = found }
                continuation.yield(.services(found.keys.sorted()))
            }
            continuation.onTermination = { _ in browser.cancel() }
            browser.start(queue: .main)
        }
    }

    public func resolve(service: String) async throws -> URL {
        guard let endpoint = lock.withLock({ endpoints[service] }) else { throw FrameError.offline }
        let parameters = NWParameters.tcp
        if let ip = parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
            ip.version = .v4
        }
        let connection = NWConnection(to: endpoint, using: parameters)
        let once = Once()
        return try await withCheckedThrowingContinuation { continuation in
            let finish: @Sendable (Result<URL, Error>) -> Void = { result in
                guard once.claim() else { return }
                connection.cancel()
                continuation.resume(with: result)
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if case .hostPort(let host, let port)? = connection.currentPath?.remoteEndpoint,
                       let url = FrameAddress.url(host: Self.text(host), port: Int(port.rawValue)) {
                        finish(.success(url))
                    } else {
                        finish(.failure(FrameError.offline))
                    }
                case .failed, .waiting:
                    finish(.failure(FrameError.offline))
                default:
                    break
                }
            }
            connection.start(queue: .global())
            DispatchQueue.global().asyncAfter(deadline: .now() + 5) { finish(.failure(FrameError.timeout)) }
        }
    }

    private static func text(_ host: NWEndpoint.Host) -> String {
        switch host {
        case .ipv4(let address): return "\(address)"
        case .ipv6(let address): return "\(address)"
        case .name(let name, _): return name
        @unknown default: return "\(host)"
        }
    }
}

private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.withLock {
            if claimed { return false }
            claimed = true
            return true
        }
    }
}
