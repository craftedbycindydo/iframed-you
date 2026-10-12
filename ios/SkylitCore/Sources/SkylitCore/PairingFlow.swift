import Foundation
import Observation

@MainActor
@Observable
public final class PairingFlow {
    public enum Step: Equatable, Sendable {
        case idle
        case requestingCode
        case awaitingCode
        case verifying
        case paired
        case failed
    }

    public nonisolated static let codeLength = 6

    public private(set) var step: Step = .idle
    public private(set) var message: String?
    public let frameName: String

    private let api: FrameAPI
    private let deviceName: String
    private let tokens: TokenStoring

    public init(frameName: String, api: FrameAPI, deviceName: String, tokens: TokenStoring) {
        self.frameName = frameName
        self.api = api
        self.deviceName = Limits.cleanName(String(deviceName.prefix(Limits.nameLength))) ?? "iPhone"
        self.tokens = tokens
    }

    public nonisolated static func isValid(code: String) -> Bool {
        code.count == codeLength && code.allSatisfy { $0.isASCII && $0.isNumber }
    }

    public func start() async {
        guard step != .requestingCode, step != .verifying else { return }
        step = .requestingCode
        message = nil
        do {
            try await api.pairStart()
            step = .awaitingCode
        } catch {
            step = .failed
            message = FrameError.from(error).userMessage
        }
    }

    public func submit(code: String) async -> PairResult? {
        guard step == .awaitingCode else { return nil }
        guard Self.isValid(code: code) else {
            message = "Enter the 6-digit code shown on the frame."
            return nil
        }
        step = .verifying
        message = nil
        do {
            let result = try await api.pairFinish(code: code, deviceName: deviceName)
            tokens.save(result.token, for: result.frameId)
            step = .paired
            return result
        } catch {
            let failure = FrameError.from(error)
            switch failure {
            case .api(429, _, _), .api(409, _, _):
                step = .failed
                message = failure.userMessage
            case .unauthorized:
                step = .awaitingCode
                message = "That code didn't match. Check the frame and try again."
            default:
                step = .awaitingCode
                message = failure.userMessage
            }
            return nil
        }
    }
}
