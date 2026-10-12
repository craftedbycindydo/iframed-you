import SwiftUI
import SkylitCore

struct ConnectScreen: View {
    @Environment(FrameSession.self) private var session
    @Environment(\.theme) private var theme
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var manualAddress = ""
    @State private var isConnectingManually = false
    @State private var hasWaited = false
    @FocusState private var addressFocused: Bool

    private var canConnectManually: Bool {
        FrameAddress.parse(manualAddress) != nil && !session.isBusy
    }

    var body: some View {
        @Bindable var session = session
        NavigationStack {
            ThemedList {
                Section {
                    FrameHero()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Space.s)
                }
                .listRowBackground(Color.clear)
                if let warning = session.warning {
                    Section {
                        RowLabel(warning, symbol: "exclamationmark.shield", symbolTint: theme.tint)
                    }
                }
                if let paired = session.paired {
                    reconnecting(paired)
                } else {
                    switch session.discovery {
                    case .permissionDenied: permissionDenied
                    case .failed(let reason): browseFailed(reason)
                    case .searching: frames
                    }
                }
                manualEntry
            }
            .listSectionSpacing(Space.l)
            .screenHeader("iFramed You", status: session.paired == nil
                          ? "Chores, shopping, photos and setup, encrypted between this phone and your frame."
                          : "Getting back in touch with your frame.")
        }
        .overlay(alignment: .bottom) {
            NoticeToast(notice: $session.notice).padding(.bottom, Space.s).stateAnimation(session.notice)
        }
        .sensoryFeedback(.error, trigger: session.notice) { _, new in new != nil }
        .sheet(isPresented: Binding(get: { session.pairing != nil }, set: { if !$0 { Task { await session.cancelPairing() } } })) {
            if let flow = session.pairing {
                PairingSheet(flow: flow)
                    .environment(\.theme, theme)
            }
        }
        .task {
            try? await Task.sleep(for: .seconds(4))
            hasWaited = true
        }
        .task(id: session.paired) {
            while !Task.isCancelled, session.paired != nil {
                try? await Task.sleep(for: .seconds(3))
                if let store = session.store {
                    if store.state == nil { await store.refresh() }
                } else {
                    await session.reconnect()
                }
            }
        }
    }

    private var searchingGlyph: some View {
        Image(systemName: "dot.radiowaves.left.and.right")
            .font(.glyph)
            .foregroundStyle(theme.tint)
            .symbolEffect(.variableColor.iterative.reversing, isActive: !reduceMotion)
            .frame(width: Size.glyph, height: Size.glyph)
            .accessibilityHidden(true)
    }

    private func reconnecting(_ paired: PairedFrame) -> some View {
        Section {
            HStack(spacing: Space.m) {
                searchingGlyph
                Text("Looking for \(paired.name)").font(.rowTitle)
            }
            if session.discovery == .permissionDenied {
                Button("Open Settings", systemImage: "gear", action: openSettings)
            }
            Button("Use a different frame", systemImage: "arrow.triangle.2.circlepath") { session.leave() }
        } footer: {
            Text(session.discovery == .permissionDenied
                 ? "Turn on Local Network for iFramed You in Settings."
                 : "Make sure the frame is on and this phone is on the same Wi-Fi.")
        }
    }

    private var frames: some View {
        Section {
            if session.frames.isEmpty {
                HStack(spacing: Space.m) {
                    searchingGlyph
                    Text(hasWaited ? "Still searching for frames" : "Searching for frames").font(.rowTitle)
                }
            } else {
                ForEach(session.frames) { frame in
                    Button {
                        Task { await session.select(frame) }
                    } label: {
                        RowLabel(frame.name, subtitle: session.hasToken(for: frame) ? "Paired with this phone" : "Tap to pair",
                                 symbol: "photo.tv", symbolTint: theme.tint) {
                            if session.isBusy { ProgressView() } else { RowChevron() }
                        }
                    }
                    .buttonStyle(RowButtonStyle())
                    .disabled(session.isBusy)
                }
            }
        } header: {
            SectionHeader("Frames nearby")
        } footer: {
            if session.frames.isEmpty {
                if hasWaited { Text("Check that the frame is on and on the same Wi-Fi as this phone.") }
            } else {
                Text("To pair, go to the frame first: open Settings › Phone app and tap Pair a phone. Then choose the frame here.")
            }
        }
    }

    private var permissionDenied: some View {
        Section {
            RowLabel("Local Network access is off", symbol: "wifi.exclamationmark", symbolTint: theme.tint)
            Button("Open Settings", systemImage: "gear", action: openSettings)
        } footer: {
            Text("iFramed You talks only to your frame, encrypted between this phone and your frame. Allow Local Network for iFramed You in Settings.")
        }
    }

    private func browseFailed(_ reason: String) -> some View {
        Section {
            RowLabel("Can't search this network", symbol: "wifi.slash", symbolTint: theme.tint)
        } footer: {
            Text("Connect this phone to Wi-Fi, or enter the frame's address below. (\(reason))")
        }
    }

    private var manualEntry: some View {
        Section {
            HStack(spacing: Space.m) {
                TextField("Address", text: $manualAddress, prompt: Text("192.168.1.20:8765"))
                    .touchTarget()
                    .onTapGesture { addressFocused = true }
                    .focused($addressFocused)
                    .keyboardType(.numbersAndPunctuation)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .onSubmit(connectManually)
                Button(action: connectManually) {
                    if isConnectingManually {
                        ProgressView()
                    } else {
                        Text("Connect")
                    }
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .touchTarget(footprint: Size.capsule)
                .disabled(!canConnectManually)
            }
        } header: {
            SectionHeader("Or enter the frame's address")
        } footer: {
            Text("Shown on the frame under Settings › Phone app.")
        }
    }

    private func connectManually() {
        guard canConnectManually else { return }
        isConnectingManually = true
        Task {
            await session.connect(manualAddress: manualAddress)
            isConnectingManually = false
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
    }
}

struct PairingSheet: View {
    @Environment(FrameSession.self) private var session
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    let flow: PairingFlow
    @State private var code = ""
    @State private var name = ""
    @FocusState private var nameFocused: Bool

    private var title: String {
        switch flow.step {
        case .naming, .starting: return "Pair with \(flow.frameName)"
        case .enteringCode: return "Type the code shown on \(flow.frameName)"
        case .confirming(let pick): return PairingFlow.tapText(pick)
        case .paired: return "Paired"
        case .failed: return "Not paired"
        }
    }

    private var guidance: String {
        switch flow.step {
        case .naming, .starting: return "First, on the frame, open Settings › Phone app and tap Pair a phone. The frame then waits two minutes."
        case .enteringCode: return "The code proves this phone is talking to your frame. Only pair phones you trust."
        case .confirming: return "The frame shows three numbers. Tap this one there. If the frame shows anything else, tap Cancel on the frame."
        case .paired: return "This phone is paired."
        case .failed: return "Nothing was saved on this phone."
        }
    }

    private var canBegin: Bool {
        flow.step == .naming && Limits.cleanDeviceName(name) != nil
    }

    var body: some View {
        NavigationStack {
            ThemedList {
                Section {
                    HStack(alignment: .top, spacing: Space.l) {
                        VStack(alignment: .leading, spacing: Space.s) {
                            Text(title).font(.hero)
                            Text(guidance).font(.rowSubtitle).foregroundStyle(Theme.secondaryLabel)
                        }
                        if !typeSize.isAccessibilitySize {
                            Spacer(minLength: 0)
                            FrameHero(width: 96)
                        }
                    }
                }
                .listRowBackground(Color.clear)
                switch flow.step {
                case .naming, .starting: naming
                case .enteringCode: codeEntry
                case .confirming(let pick): confirming(pick)
                case .paired: EmptyView()
                case .failed: failed
                }
            }
            .navigationTitle("Pair with frame")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(flow.step == .failed ? "Close" : "Cancel") { dismiss() }
                }
            }
        }
        .sensoryFeedback(.error, trigger: flow.message) { _, new in new != nil }
        .sensoryFeedback(.success, trigger: flow.step) { _, new in
            if case .confirming = new { return true }
            return false
        }
        .onChange(of: flow.message) { _, message in
            if message != nil { code = "" }
        }
        .onAppear { name = flow.suggestedName }
        .presentationDetents([.large])
        .interactiveDismissDisabled(flow.step != .failed)
    }

    private var naming: some View {
        Section {
            TextField("Name this phone", text: $name, prompt: Text("Maya's iPhone"))
                .touchTarget()
                .onTapGesture { nameFocused = true }
                .focused($nameFocused)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .onSubmit(begin)
                .onChange(of: name) { _, new in
                    if Limits.clipped(new, to: Limits.deviceNameLength) != new { name = Limits.clipped(new, to: Limits.deviceNameLength) }
                }
                .disabled(flow.step == .starting)
            Button(action: begin) {
                HStack {
                    Label("Pair", systemImage: "link")
                    Spacer()
                    if flow.step == .starting { ProgressView() }
                }
            }
            .disabled(!canBegin)
        } header: {
            SectionHeader("Name this phone")
        } footer: {
            if let message = flow.message {
                Text(message).foregroundStyle(theme.tint)
            } else {
                Text("The frame lists paired phones by this name.")
            }
        }
    }

    private var codeEntry: some View {
        Section {
            CodeEntry(code: $code) { entered in
                Task { await session.submit(code: entered) }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Space.s)
        } footer: {
            if let message = flow.message {
                Text(message).foregroundStyle(theme.tint)
            } else {
                Text("You have three tries.")
            }
        }
        .listRowBackground(Color.clear)
    }

    private func confirming(_ pick: String) -> some View {
        Section {
            Text(pick)
                .font(.screenTitle)
                .monospacedDigit()
                .frame(maxWidth: .infinity)
                .padding(.vertical, Space.l)
                .accessibilityHidden(true)
                .listRowSeparator(.hidden)
            HStack(spacing: Space.m) {
                ProgressView()
                Text("Waiting for the tap on the frame")
            }
        }
    }

    private var failed: some View {
        let symbol = switch flow.message {
        case PairingFlow.timeoutText: "clock"
        case PairingFlow.cancelledText: "xmark.circle"
        default: "exclamationmark.triangle"
        }
        return Section {
            RowLabel(flow.message ?? PairingFlow.failureText, symbol: symbol, symbolTint: theme.tint)
            Button("Try again", systemImage: "arrow.clockwise") { flow.reset() }
        } footer: {
            Text("On the frame, tap Pair a phone again first.")
        }
    }

    private func begin() {
        guard canBegin else { return }
        nameFocused = false
        Task { await session.startPairing(name: name) }
    }
}
