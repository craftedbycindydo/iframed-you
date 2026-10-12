import SwiftUI
import SkylitCore

struct ClimateScreen: View {
    @Environment(ClimateStore.self) private var store
    @Environment(\.theme) private var theme
    @Environment(\.scenePhase) private var scenePhase
    @State private var email = ""
    @State private var password = ""
    @FocusState private var focus: Field?

    private enum Field {
        case email
        case password
    }

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            ThemedList {
                switch store.phase {
                case .signedOut:
                    signIn
                case .loading:
                    if store.trouble == nil {
                        Section {
                            HStack(spacing: Space.m) {
                                ProgressView()
                                Text("Getting your thermostats").font(.rowTitle).foregroundStyle(Theme.secondaryLabel)
                            }
                        }
                    } else {
                        unreachable
                    }
                case .locked, .ready:
                    thermostats
                }
            }
            .listSectionSpacing(Space.l)
            .stateAnimation(store.phase)
            .refreshable { await store.refresh() }
            .screenHeader("Climate", status: status, statusSymbol: statusSymbol) {
                if store.phase != .signedOut {
                    Menu {
                        Button("Refresh", systemImage: "arrow.clockwise") {
                            Task { await store.refresh() }
                        }
                        Button("Sign Out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                            Task { await store.signOut() }
                        }
                    } label: {
                        Label("More", systemImage: "ellipsis")
                    }
                    .headerAction()
                }
            }
        }
        .overlay(alignment: .bottom) {
            NoticeToast(notice: $store.notice).padding(.bottom, Space.s).stateAnimation(store.notice)
        }
        .sensoryFeedback(.error, trigger: store.notice) { _, new in new != nil }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await store.runPolling()
        }
    }

    private var status: String? {
        switch store.phase {
        case .signedOut: return "Sign in to Honeywell to see your thermostats here"
        case .loading: return store.trouble == nil ? nil : "Can't reach Honeywell right now"
        case .locked(let until): return "Sign-in paused by Honeywell until \(until.formatted(date: .omitted, time: .shortened))"
        case .ready: break
        }
        let updated = store.lastUpdated.map { " · updated \($0.formatted(date: .omitted, time: .shortened))" } ?? ""
        if store.trouble == .offline { return "No connection" + updated }
        if store.trouble == .unavailable { return "Honeywell isn't answering" + updated }
        if store.isStale { return "Checking" + updated }
        guard let outdoor = store.thermostats.first(where: { $0.outdoorTemperature != nil }), let temperature = outdoor.outdoorTemperature else { return nil }
        let humidity = outdoor.outdoorHumidity.map { " · \(Int($0.rounded()))% humidity" } ?? ""
        return "Outside \(Climate.degrees(temperature, outdoor.units))" + humidity
    }

    private var statusSymbol: String? {
        switch store.phase {
        case .signedOut: return "thermometer.medium"
        case .loading: return store.trouble == nil ? nil : "wifi.slash"
        case .locked: return "lock"
        case .ready: break
        }
        if store.trouble != nil { return "wifi.slash" }
        return store.isStale ? "arrow.triangle.2.circlepath" : "cloud.sun"
    }

    @ViewBuilder private var signIn: some View {
        Section {
            TextField("Email", text: $email)
                .textContentType(.username)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focus, equals: .email)
                .submitLabel(.next)
                .onSubmit { focus = .password }
            SecureField("Password", text: $password)
                .textContentType(.password)
                .focused($focus, equals: .password)
                .submitLabel(.go)
                .onSubmit(submit)
            Button(action: submit) {
                HStack {
                    Text(store.isSigningIn ? "Signing In" : "Sign In").fontWeight(.semibold)
                    Spacer()
                    if store.isSigningIn { ProgressView() }
                }
            }
            .disabled(!canSubmit)
        } header: {
            SectionHeader("Total Connect Comfort account")
        } footer: {
            if let problem = store.signInError {
                Label(problem, systemImage: "exclamationmark.circle").foregroundStyle(Theme.destructive)
            } else {
                Text("Your password stays in this iPhone's Keychain and is sent only to Honeywell.")
            }
        }
    }

    private var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty && !store.isSigningIn
    }

    private func submit() {
        guard canSubmit else { return }
        focus = nil
        let entered = password
        Task {
            await store.signIn(username: email, password: entered)
            if store.phase != .signedOut { password = "" }
        }
    }

    private var unreachable: some View {
        Section {
            ContentUnavailableView {
                Label("Can't reach Honeywell", systemImage: "wifi.slash")
            } description: {
                Text("Your thermostats will show here once the connection is back.")
            } actions: {
                Button("Try Again") { Task { await store.refresh() } }
            }
        }
        .listRowBackground(Color.clear)
    }

    @ViewBuilder private var thermostats: some View {
        if case .locked(let until) = store.phase, store.thermostats.isEmpty {
            Section {
                RowLabel("Too many sign-in attempts", subtitle: "Honeywell pauses every app, including Total Connect Comfort. Your thermostats come back after \(until.formatted(date: .omitted, time: .shortened)).",
                         symbol: "lock", symbolTint: Theme.secondaryLabel)
            }
        }
        if store.phase == .ready, store.thermostats.isEmpty {
            Section {
                ContentUnavailableView {
                    Label("No thermostats", systemImage: "thermometer.medium.slash")
                } description: {
                    Text("This Honeywell account has no thermostats.")
                }
            }
            .listRowBackground(Color.clear)
        }
        ForEach(store.thermostats) { thermostat in
            Section {
                ThermostatTile(store: store, thermostat: thermostat)
            }
        }
    }
}

enum Climate {
    static func degrees(_ value: Double, _ units: TccUnits) -> String {
        let rounded = (value * 2).rounded() / 2
        return (rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.1f", rounded)) + "°"
    }

    static func time(minutes: Int) -> String {
        let start = Calendar.current.startOfDay(for: Date())
        return start.addingTimeInterval(TimeInterval(minutes * 60)).formatted(date: .omitted, time: .shortened)
    }

    static func modeName(_ mode: TccMode?) -> String {
        switch mode {
        case .heat: return "Heat"
        case .cool: return "Cool"
        case .off: return "Off"
        case .auto: return "Auto"
        case .emergencyHeat: return "Emergency heat"
        case nil: return "Unknown mode"
        }
    }

    static func fanName(_ mode: TccFanMode) -> String {
        switch mode {
        case .auto: return "Auto"
        case .on: return "On"
        case .circulate: return "Circulate"
        case .followSchedule: return "Follows schedule"
        }
    }

    static func holdName(_ hold: TccHold?) -> String {
        switch hold {
        case .schedule, nil: return "Following schedule"
        case .permanent: return "Permanent hold"
        case .temporary(let minutes): return minutes.map { "Hold until \(time(minutes: $0))" } ?? "Temporary hold"
        }
    }
}

private struct ThermostatTile: View {
    @Environment(\.theme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .footnote) private var dot = Space.s
    let store: ClimateStore
    let thermostat: TccThermostat

    private var enabled: Bool { store.canControl && thermostat.isOnline }
    private var accent: Color { thermostat.isOnline ? (thermostat.activeSetpoint == .cool ? Theme.cooling : Theme.heating) : Theme.tertiaryLabel }
    private var isRunning: Bool { thermostat.running == .heating || thermostat.running == .cooling }
    private var onHold: Bool { thermostat.hold != nil && thermostat.hold != .schedule }
    private var indoor: String { thermostat.indoorTemperature.map { Climate.degrees($0, thermostat.units) } ?? "–" }

    private var target: (which: TccSetpoint, value: Double, limits: ClosedRange<Double>)? {
        guard thermostat.isOnline, let which = thermostat.activeSetpoint, let value = thermostat.setpoint(which),
              let limits = thermostat.range(which) else { return nil }
        return (which, value, limits)
    }

    private var activity: String {
        guard thermostat.isOnline else { return "Offline" }
        let mode = Climate.modeName(thermostat.mode)
        switch thermostat.running {
        case .heating: return "Heating now"
        case .cooling: return "Cooling now"
        default: return mode
        }
    }

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Space.m))
            : AnyLayout(HStackLayout(spacing: Space.m))
        layout {
            identity.frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: Space.s) {
                Text(indoor)
                    .font(.figure)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(enabled ? Theme.label : Theme.secondaryLabel)
                if typeSize.isAccessibilitySize { Spacer(minLength: 0) }
                if let target { stepper(target) }
                menu
            }
            .fixedSize(horizontal: !typeSize.isAccessibilitySize, vertical: false)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }
        .listRowInsets(EdgeInsets(top: Space.s, leading: Space.l, bottom: Space.s, trailing: Space.xs))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(thermostat.name), \(activity)")
        .accessibilityValue((target.map { "\(indoor), set to \(Climate.degrees($0.value, thermostat.units)), " } ?? "\(indoor), ") + Climate.holdName(thermostat.hold))
        .accessibilityHint(target == nil ? "" : "Swipe up or down to change the setpoint")
        .accessibilityAdjustableAction { direction in
            store.adjust(thermostat.id, by: direction == .increment ? 1 : -1)
        }
        .accessibilityActions {
            if onHold {
                Button("Resume schedule") { Task { await store.resumeSchedule(thermostat.id) } }
            }
            ForEach(switchableModes, id: \.self) { mode in
                Button("Switch to \(Climate.modeName(mode))") { Task { await store.setMode(thermostat.id, to: mode) } }
            }
        }
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(thermostat.name).font(.rowTitle).fontWeight(.semibold).lineLimit(1)
            HStack(spacing: Space.xs) {
                Circle().fill(accent).frame(width: dot, height: dot).opacity(isRunning || !thermostat.isOnline ? 1 : 0.4)
                Text(activity).font(.note).foregroundStyle(Theme.secondaryLabel).lineLimit(1)
            }
        }
    }

    private func stepper(_ target: (which: TccSetpoint, value: Double, limits: ClosedRange<Double>)) -> some View {
        HStack(spacing: Space.xs) {
            StepButton(symbol: "minus", label: "Lower \(thermostat.name) setpoint", disabled: target.value <= target.limits.lowerBound || !enabled) {
                store.adjust(thermostat.id, by: -1)
            }
            Text(Climate.degrees(target.value, thermostat.units))
                .font(.rowTitle)
                .fontWeight(.semibold)
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
                .contentTransition(.numericText())
                .stateAnimation(target.value)
                .frame(minWidth: Space.xxl)
                .foregroundStyle(enabled ? Theme.label : Theme.secondaryLabel)
            StepButton(symbol: "plus", label: "Raise \(thermostat.name) setpoint", disabled: target.value >= target.limits.upperBound || !enabled) {
                store.adjust(thermostat.id, by: 1)
            }
        }
        .sensoryFeedback(.selection, trigger: target.value)
    }

    private var switchableModes: [TccMode] {
        [TccMode.heat, .cool].filter { thermostat.allowedModes.contains($0) && $0 != thermostat.mode }
    }

    private var menu: some View {
        Menu {
            Text(Climate.holdName(thermostat.hold))
            if onHold {
                Button("Resume schedule", systemImage: "calendar") {
                    Task { await store.resumeSchedule(thermostat.id) }
                }
                .disabled(!enabled)
            }
            if !switchableModes.isEmpty || thermostat.activeSetpoint != nil {
                Picker("Mode", selection: Binding(get: { thermostat.mode }, set: { chosen in
                    guard let chosen, chosen != thermostat.mode else { return }
                    Task { await store.setMode(thermostat.id, to: chosen) }
                })) {
                    if thermostat.allowedModes.contains(.heat) { Label("Heat", systemImage: "flame").tag(TccMode?.some(.heat)) }
                    if thermostat.allowedModes.contains(.cool) { Label("Cool", systemImage: "snowflake").tag(TccMode?.some(.cool)) }
                }
                .pickerStyle(.menu)
                .disabled(!enabled)
            }
            if let fan = thermostat.fanMode {
                Section {
                    Label("Fan · \(Climate.fanName(fan))" + (thermostat.isFanRunning ? " · running" : ""), systemImage: "fan")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
                .foregroundStyle(theme.tint)
                .frame(width: Size.touch, height: Size.touch)
                .contentShape(Rectangle())
        }
        .menuOrder(.fixed)
        .sensoryFeedback(.selection, trigger: thermostat.mode)
        .accessibilityLabel("\(thermostat.name) settings")
    }
}

private struct StepButton: View {
    @Environment(\.theme) private var theme
    @ScaledMetric(relativeTo: .subheadline) private var disc = Size.control + Space.xs
    let symbol: String
    let label: String
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.bold))
                .frame(width: disc, height: disc)
                .modifier(GlassSurface())
                .frame(width: max(Size.touch, disc), height: max(Size.touch, disc))
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .tint(theme.tint)
        .disabled(disabled)
        .accessibilityLabel(label)
    }
}

extension Launch {
    @MainActor
    static func makeClimate() -> ClimateStore {
        #if DEBUG
        if Demo.isOn { return ClimateDemo.store() }
        #endif
        return ClimateStore(client: TccClient(transport: TccURLSessionTransport(), defaults: .standard), credentials: TccCredentialStore())
    }
}

#if DEBUG
enum ClimateDemo {
    @MainActor
    static func store() -> ClimateStore {
        let mode = UserDefaults.standard.string(forKey: "demoClimate") ?? "normal"
        let server = FakeTccServer.sample()
        let saved = InMemoryTccCredentialStore(mode == "signedOut" ? nil : FakeTccServer.demoCredentials)
        switch mode {
        case "locked": server.setLogin(.tooManyAttempts)
        case "thermostatOffline": server.update(1002) { $0["communicationLost"] = true }
        case "many":
            server.addThermostat(id: 1003, name: "Studio", ui: FakeTccServer.ui(mode: 1, indoor: 66, heat: 68, cool: 78, status: 0, running: 1))
            server.addThermostat(id: 1004, name: "Guest room", ui: FakeTccServer.ui(mode: 2, indoor: 71, heat: 65, cool: 76, status: 0))
        default: break
        }
        let store = ClimateStore(client: TccClient(transport: server), credentials: saved)
        if mode == "offline" {
            Task {
                await store.start()
                await store.refresh()
                server.setUnreachable(true)
                await store.refresh()
            }
        }
        return store
    }
}
#endif
