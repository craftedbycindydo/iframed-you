import Foundation
import Observation

@MainActor
@Observable
public final class PairingFlow {
    public enum Step: Equatable, Sendable {
        case naming
        case starting
        case enteringCode
        case confirming(pick: String)
        case paired
        case failed
    }

    public nonisolated static let codeLength = 6
    public nonisolated static let attempts = 3
    public nonisolated static let failureText = "This phone did not pair. Another device may be trying. Tap Cancel on the frame; do not tap a number."
    public nonisolated static let windowText = "The frame is not ready to pair. On the frame, open Settings, then Phone app, and tap Pair a phone. Then tap Pair here."
    public nonisolated static let nameText = "Give this phone a name of 1 to 40 characters."

    public nonisolated static func tapText(_ pick: String) -> String {
        "Tap \(pick) on the frame"
    }

    public nonisolated static func isValid(code: String) -> Bool {
        code.utf8.count == codeLength && code.utf8.allSatisfy { (48...57).contains($0) }
    }

    public private(set) var step: Step = .naming
    public private(set) var message: String?
    public private(set) var triesLeft = PairingFlow.attempts
    public let frameName: String

    public var suggestedName: String { names.name }

    private struct Attempt {
        let token: String
        let fp: String
        let code: String
        let pick: String
    }

    private let api: FrameAPI
    private let probe: FrameAPI
    private let fingerprint: @Sendable () -> String?
    private let tokens: TokenStoring
    private let names: DeviceNameStore
    private let pollInterval: Duration
    private let patience: Duration
    private var session: String?
    private var attempt: Attempt?

    public init(frameName: String, api: FrameAPI, probe: FrameAPI, fingerprint: @escaping @Sendable () -> String?,
                tokens: TokenStoring, names: DeviceNameStore, pollInterval: Duration = .seconds(1), patience: Duration = .seconds(180)) {
        self.frameName = Limits.display(frameName)
        self.api = api
        self.probe = probe
        self.fingerprint = fingerprint
        self.tokens = tokens
        self.names = names
        self.pollInterval = pollInterval
        self.patience = patience
    }

    public func begin(name: String) async {
        guard step == .naming else { return }
        guard let deviceName = Limits.cleanDeviceName(name) else {
            message = Self.nameText
            return
        }
        names.name = deviceName
        step = .starting
        message = nil
        do {
            guard try await probe.info().pairing else { return retry(Self.windowText) }
        } catch {
            return retry(FrameError.from(error).userMessage)
        }
        do {
            let nP = try PairingCrypto.randomBytes()
            let token = try PairingCrypto.randomBytes()
            let started: PairSession
            do {
                started = try await api.pairStart(commit: PairingCrypto.sha256(nP), tokenHash: PairingCrypto.sha256(token), deviceName: deviceName)
            } catch let failure as FrameError where failure.isConnectivity {
                return retry(failure.userMessage)
            }
            guard Hex.isValid(started.session, bytes: 16) else { throw FrameError.invalidResponse }
            session = started.session
            guard step == .starting else { return await cancelOnFrame() }
            guard let nF = Hex.decode(started.nF, bytes: 32), let fp = fingerprint(), let fpRaw = Hex.decode(fp, bytes: Pin.bytes) else {
                throw FrameError.invalidResponse
            }
            try await api.pairReveal(session: started.session, nP: Hex.encode(nP))
            guard step == .starting else { return await cancelOnFrame() }
            let derived = PairingCrypto.derive(nP: nP, nF: nF, fpRaw: fpRaw)
            attempt = Attempt(token: Hex.encode(token), fp: fp, code: derived.code, pick: derived.pick)
            step = .enteringCode
        } catch {
            await fail()
        }
    }

    public func submit(code: String) async {
        guard step == .enteringCode, let attempt else { return }
        guard Self.isValid(code: code) else {
            message = "Enter the 6-digit code shown on the frame."
            return
        }
        guard PairingCrypto.constantTimeEquals(code, attempt.code) else {
            triesLeft -= 1
            if triesLeft <= 0 {
                await fail()
            } else {
                message = triesLeft == 1 ? "That code didn't match. 1 try left." : "That code didn't match. \(triesLeft) tries left."
            }
            return
        }
        message = nil
        step = .confirming(pick: attempt.pick)
    }

    public func awaitResult() async -> (frame: PairedFrame, credential: FrameCredential)? {
        guard case .confirming = step, let attempt, let session else { return nil }
        let clock = ContinuousClock()
        let deadline = clock.now + patience
        while true {
            do {
                let result = try await api.pairResult(session: session)
                guard case .confirming = step else { return nil }
                if let result {
                    guard result.frameId == Pin.frameId(for: attempt.fp) else {
                        await fail()
                        return nil
                    }
                    let credential = FrameCredential(token: attempt.token, fp: attempt.fp)
                    tokens.save(credential)
                    self.session = nil
                    self.attempt = nil
                    step = .paired
                    return (PairedFrame(frameId: credential.frameId, name: Limits.display(result.name)), credential)
                }
            } catch let failure as FrameError where failure.isConnectivity {
                guard case .confirming = step else { return nil }
            } catch {
                guard case .confirming = step else { return nil }
                await fail()
                return nil
            }
            guard clock.now < deadline else {
                await fail()
                return nil
            }
            try? await Task.sleep(for: pollInterval)
            guard case .confirming = step else { return nil }
        }
    }

    public func abandon() async {
        guard step != .paired, step != .failed else { return }
        step = .failed
        message = nil
        attempt = nil
        await cancelOnFrame()
    }

    private func retry(_ text: String) {
        step = .naming
        message = text
    }

    private func fail() async {
        step = .failed
        message = Self.failureText
        attempt = nil
        await cancelOnFrame()
    }

    private func cancelOnFrame() async {
        guard let id = session else { return }
        session = nil
        try? await api.pairCancel(session: id)
    }
}
