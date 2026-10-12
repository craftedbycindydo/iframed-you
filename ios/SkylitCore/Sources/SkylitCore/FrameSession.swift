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

    public private(set) var frames: [DiscoveredFrame] = []
    public private(set) var discovery: Discovery = .searching
    public private(set) var paired: PairedFrame?
    public private(set) var store: FrameStore?
    public private(set) var pairing: PairingFlow?
    public private(set) var isBusy = false
    public var notice: String?

    private let browser: FrameBrowsing
    private let transport: HTTPTransport
    private let tokens: TokenStoring
    private let pairedStore: PairedFrameStore
    private let deviceName: String
    private var manualURLs: [String: URL] = [:]
    private var services: [String: String] = [:]
    private var pairingURL: URL?

    public init(browser: FrameBrowsing, transport: HTTPTransport, tokens: TokenStoring,
                pairedStore: PairedFrameStore, deviceName: String) {
        self.browser = browser
        self.transport = transport
        self.tokens = tokens
        self.pairedStore = pairedStore
        self.deviceName = deviceName
        if let saved = pairedStore.current, tokens.token(for: saved.frameId) != nil {
            paired = saved
        }
    }

    public func hasToken(for frame: DiscoveredFrame) -> Bool {
        tokens.token(for: frame.frameId) != nil
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
            discovery = .failed(reason)
        case .services(let names):
            discovery = .searching
            var found: [DiscoveredFrame] = []
            var owners: [String: String] = [:]
            for name in names {
                guard let (info, _) = await identify(service: name) else { continue }
                found.append(DiscoveredFrame(frameId: info.frameId, name: info.name))
                if owners[info.frameId] == nil { owners[info.frameId] = name }
            }
            services = owners
            frames = DiscoveredFrame.unique(found)
            if store == nil {
                await connectPaired()
            } else if store?.link == .offline {
                await store?.refresh()
            }
        }
    }

    private func locate(_ frameId: String) async -> URL? {
        if let service = services[frameId], let (info, url) = await identify(service: service), info.frameId == frameId {
            return url
        }
        return manualURLs[frameId]
    }

    private func identify(service: String) async -> (FrameInfo, URL)? {
        guard let url = try? await browser.resolve(service: service),
              let info = try? await FrameAPI(baseURL: url, transport: transport).info() else { return nil }
        return (info, url)
    }

    private func connectPaired() async {
        guard let paired, store == nil, let token = tokens.token(for: paired.frameId),
              let url = await locate(paired.frameId) else { return }
        await open(paired, url: url, token: token)
    }

    public func select(_ frame: DiscoveredFrame) async {
        isBusy = true
        defer { isBusy = false }
        guard let url = await locate(frame.frameId) else {
            notice = "Couldn't reach \(frame.name). Make sure it is on and on the same Wi-Fi."
            return
        }
        if let token = tokens.token(for: frame.frameId) {
            await open(PairedFrame(frameId: frame.frameId, name: frame.name), url: url, token: token)
        } else {
            pairingURL = url
            let flow = PairingFlow(frameName: frame.name, api: FrameAPI(baseURL: url, transport: transport),
                                   deviceName: deviceName, tokens: tokens)
            pairing = flow
            await flow.start()
        }
    }

    public func connect(manualAddress text: String) async {
        guard let url = FrameAddress.parse(text) else {
            notice = "Enter the frame's address, for example 192.168.1.20:8765."
            return
        }
        isBusy = true
        do {
            let info = try await FrameAPI(baseURL: url, transport: transport).info()
            manualURLs[info.frameId] = url
            isBusy = false
            await select(DiscoveredFrame(frameId: info.frameId, name: info.name))
        } catch {
            isBusy = false
            notice = "No frame answered at that address. Check it and try again."
        }
    }

    public func submit(code: String) async {
        guard let flow = pairing, let url = pairingURL, let result = await flow.submit(code: code) else { return }
        pairing = nil
        await open(PairedFrame(frameId: result.frameId, name: result.name), url: url, token: result.token)
        if tokens.token(for: result.frameId) == nil {
            notice = "Paired, but this phone couldn't save the pairing. You'll need a new code next time."
        }
    }

    public func cancelPairing() {
        pairing = nil
        pairingURL = nil
    }

    private func open(_ frame: PairedFrame, url: URL, token: String) async {
        paired = frame
        pairedStore.current = frame
        let opened = FrameStore(frame: frame, api: FrameAPI(baseURL: url, token: token, transport: transport))
        opened.onUnauthorized = { [weak self] in self?.handleRevoked() }
        opened.relocate = { [weak self] in await self?.locate(frame.frameId) }
        store = opened
        await opened.refresh()
    }

    private func handleRevoked() {
        guard let frame = paired else { return }
        tokens.removeToken(for: frame.frameId)
        leave()
        notice = "This phone was removed from \(frame.name). Pair again to continue."
    }

    public func forget() {
        if let frame = paired { tokens.removeToken(for: frame.frameId) }
        leave()
    }

    public func leave() {
        store = nil
        paired = nil
        pairedStore.current = nil
    }
}
