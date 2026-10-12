import Foundation
import Observation

@MainActor
@Observable
public final class FrameSession {
    public enum Discovery: Equatable, Sendable {
        case searching
        case permissionDenied
        case failed(String)
    }

    public nonisolated static let updatedText = "The frame was updated. Pair again for a secure connection."

    public nonisolated static func impostorText(_ name: String) -> String {
        "Another device on this Wi-Fi is claiming to be \(name). Nothing was sent."
    }

    public nonisolated static func unpairOfflineText(_ name: String) -> String {
        "This phone forgot \(name), but \(name) couldn't be reached. Remove this phone under Settings › Phone app on the frame."
    }

    public private(set) var frames: [DiscoveredFrame] = []
    public private(set) var discovery: Discovery = .searching
    public private(set) var paired: PairedFrame?
    public private(set) var store: FrameStore?
    public private(set) var pairing: PairingFlow?
    public private(set) var isBusy = false
    public private(set) var warning: String?
    public var notice: String?

    private struct Advert {
        let url: URL
        let info: FrameInfo
        let fp: String

        var isConsistent: Bool { info.frameId == Pin.frameId(for: fp) }
    }

    private let browser: FrameBrowsing
    private let connector: FrameConnecting
    private let tokens: TokenStoring
    private let pairedStore: PairedFrameStore
    private let deviceNames: DeviceNameStore
    private let pollInterval: Duration
    private var adverts: [Advert] = []
    private var manual: [String: URL] = [:]
    private var pairingURL: URL?
    private var reconnecting: Task<Void, Never>?

    public init(browser: FrameBrowsing, connector: FrameConnecting, tokens: TokenStoring,
                pairedStore: PairedFrameStore, deviceNames: DeviceNameStore, pollInterval: Duration = .seconds(1)) {
        self.browser = browser
        self.connector = connector
        self.tokens = tokens
        self.pairedStore = pairedStore
        self.deviceNames = deviceNames
        self.pollInterval = pollInterval
        if tokens.removeLegacy() { warning = Self.updatedText }
        if let saved = pairedStore.current {
            if tokens.credential(for: saved.frameId) != nil {
                paired = saved
            } else {
                pairedStore.current = nil
            }
        }
    }

    public func hasToken(for frame: DiscoveredFrame) -> Bool {
        tokens.credential(for: frame.frameId) != nil
    }

    public func run() async {
        for await event in browser.events() {
            await receive(event)
        }
    }

    public func receive(_ event: BrowseEvent) async {
        switch event {
        case .permissionDenied:
            discovery = .permissionDenied
        case .failed(let reason):
            discovery = .failed(Limits.display(reason, limit: Limits.noteLength))
        case .services(let names):
            discovery = .searching
            var found: [Advert] = []
            for name in names {
                guard let url = try? await browser.resolve(service: name), let advert = await probe(url) else { continue }
                found.append(advert)
            }
            adverts = found
            frames = DiscoveredFrame.unique(found.filter(\.isConsistent).map { DiscoveredFrame(frameId: $0.info.frameId, name: $0.info.name) })
            if store == nil {
                await connectPaired()
            } else if store?.state == nil || store?.link == .offline {
                await store?.refresh()
            }
        }
    }

    private func probe(_ url: URL) async -> Advert? {
        let transport = connector.probe()
        guard let info = try? await FrameAPI(baseURL: url, transport: transport).info(),
              let fp = transport.fingerprint, Pin.isValid(fp) else { return nil }
        return Advert(url: url, info: info, fp: fp)
    }

    private func candidates(_ frameId: String) -> [URL] {
        var urls = adverts.filter { $0.info.frameId == frameId }.map(\.url)
        if let url = manual[frameId], !urls.contains(url) { urls.append(url) }
        return urls
    }

    private func locate(_ frame: PairedFrame, pin: String) async -> URL? {
        let transport = connector.pinned(pin)
        var match: URL?
        var mismatch = false
        let advertised = candidates(frame.frameId)
        for url in advertised {
            do {
                _ = try await FrameAPI(baseURL: url, transport: transport).info()
                match = match ?? url
            } catch FrameError.pinMismatch {
                mismatch = true
            } catch {
                continue
            }
        }
        if match == nil, !mismatch, let stored = frame.address, !advertised.contains(stored) {
            do {
                _ = try await FrameAPI(baseURL: stored, transport: transport).info()
                match = stored
            } catch FrameError.pinMismatch {
                if let other = await probe(stored), other.info.frameId == frame.frameId || other.info.name == frame.name { mismatch = true }
            } catch {}
        }
        if mismatch {
            let text = Self.impostorText(frame.name)
            if warning != text { store?.notice = text }
            warning = text
        } else if match != nil {
            warning = nil
        }
        return match
    }

    private func connectPaired() async {
        if let running = reconnecting {
            await running.value
            return
        }
        guard let paired, store == nil, let credential = tokens.credential(for: paired.frameId) else { return }
        let attempt = Task {
            guard let url = await self.locate(paired, pin: credential.fp), self.store == nil, self.paired?.frameId == paired.frameId else { return }
            await self.open(paired, url: url, credential: credential)
        }
        reconnecting = attempt
        await attempt.value
        reconnecting = nil
    }

    public func reconnect() async {
        await connectPaired()
    }

    public func select(_ frame: DiscoveredFrame) async {
        isBusy = true
        defer { isBusy = false }
        let unreachable = "Couldn't reach \(frame.name). Make sure it is on and on the same Wi-Fi."
        if let credential = tokens.credential(for: frame.frameId) {
            let target = PairedFrame(frameId: frame.frameId, name: frame.name)
            if let url = await locate(target, pin: credential.fp) {
                await open(target, url: url, credential: credential)
            } else if warning != Self.impostorText(frame.name) {
                notice = unreachable
            }
            return
        }
        guard let url = candidates(frame.frameId).first else {
            notice = unreachable
            return
        }
        let transport = connector.pairing()
        pairingURL = url
        pairing = PairingFlow(frameName: frame.name, api: FrameAPI(baseURL: url, transport: transport),
                              probe: FrameAPI(baseURL: url, transport: connector.probe()),
                              fingerprint: { transport.fingerprint }, tokens: tokens, names: deviceNames, pollInterval: pollInterval)
    }

    public func connect(manualAddress text: String) async {
        guard let url = FrameAddress.parse(text) else {
            notice = "Enter the frame's address, for example 192.168.1.20:8765."
            return
        }
        isBusy = true
        let advert = await probe(url)
        isBusy = false
        guard let advert, advert.isConsistent || tokens.credential(for: advert.info.frameId) != nil else {
            notice = "No frame answered at that address. Check it and try again."
            return
        }
        manual[advert.info.frameId] = url
        await select(DiscoveredFrame(frameId: advert.info.frameId, name: advert.info.name))
    }

    public func startPairing(name: String) async {
        await pairing?.begin(name: name)
    }

    public func submit(code: String) async {
        guard let flow = pairing, let url = pairingURL else { return }
        await flow.submit(code: code)
        guard let result = await flow.awaitResult(), pairing === flow else { return }
        pairing = nil
        pairingURL = nil
        warning = nil
        await open(result.frame, url: url, credential: result.credential)
        if tokens.credential(for: result.frame.frameId) == nil {
            notice = "Paired, but this phone couldn't save the pairing. You'll need to pair again next time."
        }
    }

    public func cancelPairing() async {
        let flow = pairing
        pairing = nil
        pairingURL = nil
        await flow?.abandon()
    }

    private func open(_ target: PairedFrame, url: URL, credential: FrameCredential) async {
        let frame = PairedFrame(frameId: target.frameId, name: target.name, address: url)
        paired = frame
        pairedStore.current = frame
        let opened = FrameStore(frame: frame, api: FrameAPI(baseURL: url, token: credential.token, transport: connector.pinned(credential.fp)))
        opened.onUnauthorized = { [weak self] in self?.handleRevoked() }
        opened.relocate = { [weak self] in await self?.locate(frame, pin: credential.fp) }
        store = opened
        await opened.refresh()
        if let warning { opened.notice = warning }
    }

    private func handleRevoked() {
        guard let frame = paired else { return }
        tokens.remove(for: frame.frameId)
        leave()
        notice = "This phone was removed from \(frame.name). Pair again to continue."
    }

    public func unpair() async {
        let name = paired?.name
        var told = true
        if let store {
            store.onUnauthorized = nil
            told = await store.unpairThisPhone()
        }
        forget()
        if !told, let name { notice = Self.unpairOfflineText(name) }
    }

    public func forget() {
        if let frame = paired { tokens.remove(for: frame.frameId) }
        leave()
    }

    public func leave() {
        store = nil
        paired = nil
        pairedStore.current = nil
    }
}
