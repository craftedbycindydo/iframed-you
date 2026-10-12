import Foundation

public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest, body: Data?, onProgress: (@Sendable (Double) -> Void)?) async throws -> (Data, HTTPURLResponse)
}

public final class URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init(configuration: URLSessionConfiguration = URLSessionTransport.lanConfiguration) {
        session = URLSession(configuration: configuration)
    }

    public static var lanConfiguration: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 300
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.waitsForConnectivity = false
        return configuration
    }

    public func send(_ request: URLRequest, body: Data?, onProgress: (@Sendable (Double) -> Void)?) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response): (Data, URLResponse)
            if let body {
                (data, response) = try await session.upload(for: request, from: body, delegate: onProgress.map(UploadProgress.init))
            } else {
                (data, response) = try await session.data(for: request)
            }
            guard let http = response as? HTTPURLResponse else { throw FrameError.invalidResponse }
            return (data, http)
        } catch {
            throw FrameError.from(error)
        }
    }
}

private final class UploadProgress: NSObject, URLSessionTaskDelegate {
    private let report: @Sendable (Double) -> Void

    init(report: @escaping @Sendable (Double) -> Void) {
        self.report = report
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard totalBytesExpectedToSend > 0 else { return }
        report(Double(totalBytesSent) / Double(totalBytesExpectedToSend))
    }
}
