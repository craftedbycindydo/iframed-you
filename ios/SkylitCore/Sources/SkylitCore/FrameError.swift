import Foundation

public enum FrameError: Error, Equatable, Sendable {
    case api(status: Int, code: String)
    case unauthorized
    case pinMismatch
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
        case .pinMismatch:
            return "Another device on this Wi-Fi is claiming to be your frame. Nothing was sent."
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
        case .api(let status, let code):
            switch code {
            case "bad_request": return "The frame didn't accept that. Check what you entered."
            case "forbidden": return "This phone isn't allowed to do that."
            case "not_found": return "That no longer exists on the frame."
            case "conflict", "pairing_busy": return "The frame can't do that right now."
            case "too_large": return "That is too large for the frame."
            case "rate_limited": return "Too many attempts. Wait a few minutes and try again."
            default: return "The frame refused that (\(status))."
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
            }
            let error: Detail
        }
        let code = (try? JSONDecoder().decode(Envelope.self, from: body))?.error.code ?? ""
        let known = code.count <= 32 && !code.isEmpty && code.utf8.allSatisfy { (97...122).contains($0) || $0 == 95 }
        return .api(status: status, code: known ? code : "http_\(status)")
    }
}
