import SwiftUI
import SkylitCore

@main
struct SkylitApp: App {
    @State private var session = Launch.makeSession()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
        }
    }
}

enum Launch {
    @MainActor
    static func makeSession() -> FrameSession {
        #if DEBUG
        if let demo = Demo.session() { return demo }
        #endif
        return FrameSession(browser: BonjourFrameBrowser(), transport: URLSessionTransport(), tokens: KeychainTokenStore(),
                            pairedStore: PairedFrameStore(), deviceName: UIDevice.current.name)
    }
}

enum MainTab: String {
    case shopping
    case photos
    case chores
    case setup
}

struct RootView: View {
    @Environment(FrameSession.self) private var session
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase

    private var appearance: FrameAppearance {
        session.store?.state?.settings.appearance ?? .standard
    }

    private var forcedScheme: ColorScheme? {
        switch appearance.mode {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    var body: some View {
        let theme = Theme(appearance: appearance, systemDark: colorScheme == .dark)
        Group {
            #if DEBUG
            if Demo.screen == "gallery" {
                GalleryScreen()
            } else {
                mainContent
            }
            #else
            mainContent
            #endif
        }
        .stateAnimation(session.store?.state != nil)
        .environment(\.theme, theme)
        .tint(theme.tint)
        .preferredColorScheme(forcedScheme)
        .task(id: scenePhase) {
            if scenePhase == .active { await session.run() }
        }
    }

    @ViewBuilder private var mainContent: some View {
        if let store = session.store, store.state != nil {
            MainTabs(store: store)
                .transition(.opacity)
        } else {
            ConnectScreen()
                .transition(.opacity)
        }
    }
}

struct MainTabs: View {
    @Environment(\.theme) private var theme
    @Environment(\.scenePhase) private var scenePhase
    @Bindable var store: FrameStore
    @State private var tab = Launch.initialTab

    var body: some View {
        TabView(selection: $tab) {
            ShoppingScreen(store: store)
                .tabItem { Label("Shopping", systemImage: "cart") }
                .tag(MainTab.shopping)
            PhotosScreen(store: store) { tab = .setup }
                .tabItem { Label("Photos", systemImage: "photo.on.rectangle.angled") }
                .tag(MainTab.photos)
            ChoresScreen(store: store)
                .tabItem { Label("Chores", systemImage: "checklist") }
                .tag(MainTab.chores)
            SetupScreen(store: store)
                .tabItem { Label("Frame", systemImage: "sun.max") }
                .tag(MainTab.setup)
        }
        .overlay(alignment: .bottom) {
            NoticeToast(notice: $store.notice)
                .padding(.bottom, Space.xxl + Space.xl)
                .stateAnimation(store.notice)
        }
        .sensoryFeedback(.error, trigger: store.notice) { _, new in new != nil }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await store.refresh()
            await store.runPolling()
        }
    }
}

extension Launch {
    static var initialTab: MainTab {
        #if DEBUG
        return Demo.screen.flatMap(MainTab.init(rawValue:)) ?? .shopping
        #else
        return .shopping
        #endif
    }
}

#if DEBUG
enum Demo {
    static var isOn: Bool { UserDefaults.standard.bool(forKey: "demoFrame") }
    static var screen: String? { isOn ? UserDefaults.standard.string(forKey: "demoScreen") : nil }
    static var scrollAnchor: String? { isOn ? UserDefaults.standard.string(forKey: "demoScroll") : nil }

    @MainActor
    static func session() -> FrameSession? {
        guard isOn else { return nil }
        let frame = DiscoveredFrame(frameId: "demo-frame", name: "Kitchen frame")
        let unpaired = ["connect", "pairing", "denied", "searching"].contains(screen ?? "")
        let events: [BrowseEvent]
        switch screen {
        case "denied": events = [.permissionDenied]
        case "searching": events = [.services([])]
        default: events = [.services(["Skylit"])]
        }
        let defaults = UserDefaults(suiteName: "skylit.demo") ?? .standard
        defaults.removePersistentDomain(forName: "skylit.demo")
        let paired = PairedFrameStore(defaults: defaults)
        let tokens = InMemoryTokenStore()
        if !unpaired {
            tokens.save(DemoFrameServer.demoToken, for: frame.frameId)
            paired.current = PairedFrame(frameId: frame.frameId, name: frame.name)
        }
        let server: DemoFrameServer
        if UserDefaults.standard.bool(forKey: "demoEmpty") {
            server = DemoFrameServer()
            server.authorize(token: DemoFrameServer.demoToken, deviceName: "Karan's iPhone")
        } else {
            server = DemoFrameServer.sample()
        }
        if UserDefaults.standard.bool(forKey: "demoOffline") {
            Task {
                try? await Task.sleep(for: .milliseconds(1500))
                server.setUnreachable(true)
            }
        }
        switch UserDefaults.standard.string(forKey: "demoICloud") {
        case "syncing": server.setICloudAlbum(name: "Family album", count: 0, lastSync: nil, syncing: true, error: nil)
        case "synced": server.setICloudAlbum(name: "Family album", count: 24, lastSync: ISO8601DateFormatter().string(from: Date(timeIntervalSinceNow: -720)), syncing: false, error: nil)
        case "error": server.setICloudAlbum(name: "Family album", count: 24, lastSync: ISO8601DateFormatter().string(from: Date(timeIntervalSinceNow: -7200)), syncing: false, error: "The album is no longer public. Turn Public Website back on in Photos.")
        case "unsupported": server.removeICloudSupport()
        default: break
        }
        let session = FrameSession(browser: StaticFrameBrowser(events: events, addresses: ["Skylit": DemoFrameServer.address]),
                                   transport: server, tokens: tokens, pairedStore: paired, deviceName: "Karan's iPhone")
        if screen == "pairing" {
            Task {
                try? await Task.sleep(for: .milliseconds(900))
                await session.select(frame)
            }
        }
        return session
    }
}
#endif
