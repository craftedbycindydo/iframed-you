import Foundation

public enum FrameError: Error, Equatable, Sendable {
    case api(status: Int, code: String, message: String)
    case unauthorized
    case timeout
    case offline
    case connectionLost
    case uploadRejected
    case cancelled
    case invalidResponse

    public var isConnectivity: Bool {
        self == .timeout || self == .offline || self == .connectionLost
    }

    public var userMessage: String {
        switch self {
        case .unauthorized:
            return "This phone is no longer paired with the frame."
        case .timeout:
            return "The frame took too long to answer. Check that it is on."
        case .uploadRejected:
            return "The frame didn't accept that photo."
        case .offline, .connectionLost:
            return "Can't reach the frame. Make sure it is on and on the same Wi-Fi."
        case .cancelled:
            return "Cancelled."
        case .invalidResponse:
            return "The frame sent something this app doesn't understand. Update the frame or the app."
        case .api(let status, let code, let message):
            switch code {
            case "not_found": return "That no longer exists on the frame."
            case "too_large": return "That is too large for the frame."
            case "rate_limited": return message.isEmpty ? "Too many attempts. Wait a few minutes and try again." : message
            default: return message.isEmpty ? "The frame refused that (\(status))." : message
            }
        }
    }

    public static func from(_ error: Error) -> FrameError {
        if let known = error as? FrameError { return known }
        if error is CancellationError { return .cancelled }
        guard let urlError = error as? URLError else { return .offline }
        switch urlError.code {
        case .timedOut: return .timeout
        case .cancelled: return .cancelled
        case .networkConnectionLost: return .connectionLost
        default: return .offline
        }
    }

    static func from(status: Int, body: Data) -> FrameError {
        if status == 401 { return .unauthorized }
        struct Envelope: Decodable {
            struct Detail: Decodable {
                let code: String?
                let message: String?
            }
            let error: Detail
        }
        let detail = (try? JSONDecoder().decode(Envelope.self, from: body))?.error
        return .api(status: status, code: detail?.code ?? "http_\(status)", message: detail?.message ?? "")
    }
}
