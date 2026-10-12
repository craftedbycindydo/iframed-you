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
                case .locked(let until):
                    locked(until)
                    thermostats
                case .ready:
                    thermostats
                }
            }
            .listSectionSpacing(Space.l)
            .stateAnimation(store.phase)
            .refreshable { await store.refresh() }
            .screenHeader("Climate", status: status, statusSymbol: statusSymbol) {
                if store.phase != .signedOut {
                    Menu {
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
        case .signedOut, .locked: return nil
        case .loading: return store.trouble == nil ? nil : "Can't reach Honeywell right now"
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
        guard store.phase == .ready else { return store.trouble == nil ? nil : "wifi.slash" }
        if store.trouble != nil { return "wifi.slash" }
        return store.isStale ? "arrow.triangle.2.circlepath" : "cloud.sun"
    }

    @ViewBuilder private var signIn: some View {
        Section {
            RowLabel("Total Connect Comfort", subtitle: "Sign in with your Honeywell account to see and adjust your thermostats here, at home or away.",
                     symbol: "thermometer.medium", symbolTint: theme.tint)
        } footer: {
            Text("Your password stays in this iPhone's Keychain and is sent only to Honeywell.")
        }
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
        } footer: {
            if let problem = store.signInError {
                Label(problem, systemImage: "exclamationmark.circle").foregroundStyle(Theme.destructive)
            }
        }
        Section {
            Button(action: submit) {
                HStack(spacing: Space.s) {
                    Text(store.isSigningIn ? "Signing In" : "Sign In").fontWeight(.semibold)
                    if store.isSigningIn { ProgressView() }
                }
                .frame(maxWidth: .infinity, minHeight: Size.control)
            }
            .disabled(!canSubmit)
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

    private func locked(_ until: Date) -> some View {
        Section {
            RowLabel("Honeywell has paused sign-in",
                     subtitle: "Too many sign-in attempts. This also blocks the Total Connect Comfort app. Trying again after \(until.formatted(date: .omitted, time: .shortened)).",
                     symbol: "lock", symbolTint: Theme.secondaryLabel)
        }
    }

    @ViewBuilder private var thermostats: some View {
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
            ThermostatSection(store: store, thermostat: thermostat)
        }
    }
}

enum Climate {
    static let heating = Color.orange
    static let cooling = Color.blue

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
}

private struct ThermostatSection: View {
    @Environment(\.theme) private var theme
    @ScaledMetric(relativeTo: .largeTitle) private var indoorSize: CGFloat = 64
    let store: ClimateStore
    let thermostat: TccThermostat

    private var enabled: Bool { store.canControl && thermostat.isOnline }
    private var accent: Color { thermostat.activeSetpoint == .cool ? Climate.cooling : Climate.heating }

    private var activity: (text: String, color: Color)? {
        guard thermostat.isOnline else { return ("Offline", Theme.secondaryLabel) }
        switch thermostat.running {
        case .heating: return ("Heating", Climate.heating)
        case .cooling: return ("Cooling", Climate.cooling)
        case .idle: return ("Idle", Theme.secondaryLabel)
        case nil: return nil
        }
    }

    var body: some View {
        Section {
            reading
            if !thermostat.isOnline {
                RowLabel("Thermostat is offline", subtitle: "Honeywell can't reach it. Check its Wi-Fi and power.", symbol: "wifi.exclamationmark",
                         symbolTint: Theme.secondaryLabel)
            } else {
                holdRow.alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                if thermostat.canSwitchHeatCool { modeRow }
                if let fan = thermostat.fanMode {
                    RowLabel("Fan", symbol: "fan", symbolTint: Theme.secondaryLabel) {
                        RowValue(text: thermostat.isFanRunning ? "\(Climate.fanName(fan)) · running" : Climate.fanName(fan))
                    }
                }
            }
        } header: {
            SectionHeader(thermostat.name) {
                if let activity {
                    HStack(spacing: Space.xs) {
                        if thermostat.running == .heating || thermostat.running == .cooling {
                            Circle().fill(activity.color).frame(width: Space.s, height: Space.s).accessibilityHidden(true)
                        }
                        Text(activity.text).foregroundStyle(Theme.secondaryLabel)
                    }
                }
            }
        }
    }

    private var reading: some View {
        HStack(alignment: .center, spacing: Space.m) {
            VStack(alignment: .leading, spacing: 0) {
                Text(thermostat.indoorTemperature.map { Climate.degrees($0, thermostat.units) } ?? "–")
                    .font(.system(size: indoorSize, weight: .semibold, design: .serif))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                Text(thermostat.indoorHumidity.map { "Indoor · \(Int($0.rounded()))% humidity" } ?? "Indoor")
                    .font(.rowSubtitle)
                    .foregroundStyle(Theme.secondaryLabel)
            }
            .opacity(enabled ? 1 : 0.5)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Indoor temperature")
            .accessibilityValue(thermostat.indoorTemperature.map { Climate.degrees($0, thermostat.units) } ?? "Unknown")
            Spacer(minLength: 0)
            if thermostat.isOnline, let which = thermostat.activeSetpoint, let target = thermostat.setpoint(which), let limits = thermostat.range(which) {
                stepper(which, target, limits)
            } else if thermostat.isOnline {
                Text(Climate.modeName(thermostat.mode)).font(.hero).foregroundStyle(Theme.secondaryLabel)
            }
        }
        .padding(.vertical, Space.xs)
    }

    private func stepper(_ which: TccSetpoint, _ target: Double, _ limits: ClosedRange<Double>) -> some View {
        HStack(spacing: Space.s) {
            stepButton("minus", "Lower", -1, disabled: target <= limits.lowerBound)
            VStack(spacing: 0) {
                Text(Climate.degrees(target, thermostat.units))
                    .font(.screenTitle)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .stateAnimation(target)
                HStack(spacing: Space.xs) {
                    Circle().fill(accent).frame(width: Space.s, height: Space.s)
                    Text(which == .heat ? "Heat to" : "Cool to").font(.note).foregroundStyle(Theme.secondaryLabel)
                }
            }
            .frame(minWidth: Size.touch + Space.xl)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(which == .heat ? "Heat setpoint" : "Cool setpoint")
            .accessibilityValue(Climate.degrees(target, thermostat.units))
            stepButton("plus", "Raise", 1, disabled: target >= limits.upperBound)
        }
        .sensoryFeedback(.selection, trigger: target)
        .opacity(enabled ? 1 : 0.5)
    }

    private func stepButton(_ symbol: String, _ label: String, _ step: Int, disabled: Bool) -> some View {
        Button {
            store.adjust(thermostat.id, by: step)
        } label: {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .frame(width: Size.touch, height: Size.touch)
                .background(theme.fill, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.borderless)
        .tint(theme.tint)
        .disabled(disabled || !enabled)
        .accessibilityLabel("\(label) \(thermostat.name) setpoint")
    }

    @ViewBuilder private var holdRow: some View {
        switch thermostat.hold {
        case .schedule:
            RowLabel("Following schedule", symbol: "calendar", symbolTint: Theme.secondaryLabel)
        case .permanent:
            RowLabel("Permanent hold", symbol: "pause.circle", symbolTint: Theme.secondaryLabel) { resume }
        case .temporary(let minutes):
            RowLabel(minutes.map { "Hold until \(Climate.time(minutes: $0))" } ?? "Temporary hold", symbol: "pause.circle",
                     symbolTint: Theme.secondaryLabel) { resume }
        case nil:
            EmptyView()
        }
    }

    private var resume: some View {
        Button("Resume schedule") {
            Task { await store.resumeSchedule(thermostat.id) }
        }
        .buttonStyle(.borderless)
        .font(.rowSubtitle.weight(.semibold))
        .frame(minHeight: Size.touch)
        .disabled(!enabled)
    }

    private var modeRow: some View {
        Picker("Mode", selection: Binding(get: { thermostat.mode }, set: { chosen in
            guard let chosen, chosen != thermostat.mode else { return }
            Task { await store.setMode(thermostat.id, to: chosen) }
        })) {
            Text("Heat").tag(TccMode?.some(.heat))
            Text("Cool").tag(TccMode?.some(.cool))
        }
        .pickerStyle(.segmented)
        .disabled(!enabled)
        .sensoryFeedback(.selection, trigger: thermostat.mode)
        .accessibilityHint(thermostat.mode == .heat || thermostat.mode == .cool ? "" : "Currently \(Climate.modeName(thermostat.mode))")
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
