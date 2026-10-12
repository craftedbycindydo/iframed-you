import Foundation
import Security

public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest, body: Data?, onProgress: (@Sendable (Double) -> Void)?) async throws -> (Data, HTTPURLResponse)
}

public protocol FrameTransport: HTTPTransport {
    var fingerprint: String? { get }
}

public protocol FrameConnecting: Sendable {
    func probe() -> FrameTransport
    func pairing() -> FrameTransport
    func pinned(_ fp: String) -> HTTPTransport
}

public enum TrustPolicy: Equatable, Sendable {
    case probe
    case pairing
    case pinned(String)
}

public final class TrustGate: @unchecked Sendable {
    private let lock = NSLock()
    private let policy: TrustPolicy
    private var seen: String?

    public init(_ policy: TrustPolicy) {
        self.policy = policy
    }

    public var fingerprint: String? {
        lock.withLock { seen }
    }

    public func accepts(leaf der: Data) -> Bool {
        let observed = Pin.fingerprint(ofCertificate: der)
        return lock.withLock {
            switch policy {
            case .probe:
                seen = observed
                return true
            case .pairing:
                if let seen { return Pin.matches(observed, pin: seen) }
                seen = observed
                return true
            case .pinned(let pin):
                guard Pin.matches(observed, pin: pin) else { return false }
                seen = observed
                return true
            }
        }
    }
}

public final class TLSConnector: FrameConnecting, @unchecked Sendable {
    private let lock = NSLock()
    private var pools: [String: URLSessionTransport] = [:]

    public init() {}

    public func probe() -> FrameTransport {
        URLSessionTransport(.probe)
    }

    public func pairing() -> FrameTransport {
        URLSessionTransport(.pairing)
    }

    public func pinned(_ fp: String) -> HTTPTransport {
        lock.withLock {
            if let pool = pools[fp] { return pool }
            let pool = URLSessionTransport(.pinned(fp))
            pools[fp] = pool
            return pool
        }
    }
}

public final class URLSessionTransport: FrameTransport, @unchecked Sendable {
    private let session: URLSession
    private let exchanges: ExchangeDelegate

    public convenience init(_ policy: TrustPolicy) {
        self.init(policy, configuration: Self.lanConfiguration)
    }

    init(_ policy: TrustPolicy, configuration: URLSessionConfiguration) {
        exchanges = ExchangeDelegate(gate: TrustGate(policy))
        session = URLSession(configuration: configuration, delegate: exchanges, delegateQueue: nil)
    }

    deinit {
        session.invalidateAndCancel()
    }

    public var fingerprint: String? {
        exchanges.gate.fingerprint
    }

    public static var lanConfiguration: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 300
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.connectionProxyDictionary = [:]
        configuration.httpAdditionalHeaders = ["User-Agent": "iFramedYou"]
        configuration.tlsMinimumSupportedProtocolVersion = .TLSv12
        configuration.waitsForConnectivity = false
        return configuration
    }

    public func send(_ request: URLRequest, body: Data?, onProgress: (@Sendable (Double) -> Void)?) async throws -> (Data, HTTPURLResponse) {
        guard request.url?.scheme == "https" else { throw FrameError.offline }
        let task = body.map { session.uploadTask(with: request, from: $0) } ?? session.dataTask(with: request)
        return try await exchanges.run(task, limit: Limits.responseBytes(for: request), onProgress: onProgress)
    }
}

final class ExchangeDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private struct Exchange {
        let limit: Int
        let onProgress: (@Sendable (Double) -> Void)?
        let finish: CheckedContinuation<(Data, HTTPURLResponse), Error>
        var data = Data()
        var isOversized = false
        var isAbandoned = false
    }

    let gate: TrustGate
    private let lock = NSLock()
    private var exchanges: [Int: Exchange] = [:]

    init(gate: TrustGate) {
        self.gate = gate
    }

    func run(_ task: URLSessionTask, limit: Int, onProgress: (@Sendable (Double) -> Void)?) async throws -> (Data, HTTPURLResponse) {
        let id = task.taskIdentifier
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { finish in
                lock.withLock { exchanges[id] = Exchange(limit: limit, onProgress: onProgress, finish: finish) }
                task.resume()
            }
        } onCancel: {
            lock.withLock { exchanges[id]?.isAbandoned = true }
            task.cancel()
        }
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        guard let trust = challenge.protectionSpace.serverTrust,
              let leaf = (SecTrustCopyCertificateChain(trust) as? [SecCertificate])?.first,
              gate.accepts(leaf: SecCertificateCopyData(leaf) as Data) else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let fits = lock.withLock {
            guard let exchange = exchanges[dataTask.taskIdentifier] else { return false }
            if response.expectedContentLength > Int64(exchange.limit) {
                exchanges[dataTask.taskIdentifier]?.isOversized = true
                return false
            }
            return true
        }
        completionHandler(fits ? .allow : .cancel)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let fits = lock.withLock {
            guard var exchange = exchanges[dataTask.taskIdentifier], !exchange.isOversized else { return false }
            if exchange.data.count + data.count > exchange.limit {
                exchange.isOversized = true
                exchange.data = Data()
            } else {
                exchange.data.append(data)
            }
            exchanges[dataTask.taskIdentifier] = exchange
            return !exchange.isOversized
        }
        if !fits { dataTask.cancel() }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard totalBytesExpectedToSend > 0 else { return }
        lock.withLock { exchanges[task.taskIdentifier]?.onProgress }?(Double(totalBytesSent) / Double(totalBytesExpectedToSend))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let exchange = lock.withLock({ exchanges.removeValue(forKey: task.taskIdentifier) }) else { return }
        if exchange.isOversized {
            exchange.finish.resume(throwing: FrameError.invalidResponse)
        } else if let error {
            let refusedByPin = (error as? URLError)?.code == .cancelled && !exchange.isAbandoned
            exchange.finish.resume(throwing: refusedByPin ? FrameError.pinMismatch : FrameError.from(error))
        } else if let response = task.response as? HTTPURLResponse {
            exchange.finish.resume(returning: (exchange.data, response))
        } else {
            exchange.finish.resume(throwing: FrameError.invalidResponse)
        }
    }
}
