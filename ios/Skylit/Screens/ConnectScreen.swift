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
                          ? "Manage chores, shopping, photos and setup over Wi-Fi."
                          : "Getting back in touch with your frame.")
        }
        .overlay(alignment: .bottom) {
            NoticeToast(notice: $session.notice).padding(.bottom, Space.s).stateAnimation(session.notice)
        }
        .sensoryFeedback(.error, trigger: session.notice) { _, new in new != nil }
        .sheet(isPresented: Binding(get: { session.pairing != nil }, set: { if !$0 { session.cancelPairing() } })) {
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
                if let store = session.store, store.state == nil { await store.refresh() }
            }
        }
    }

    private var searchingGlyph: some View {
        Image(systemName: "dot.radiowaves.left.and.right")
            .font(.title3)
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
            if session.frames.isEmpty, hasWaited {
                Text("Check that the frame is on, running Skylit, and on the same Wi-Fi as this phone.")
            }
        }
    }

    private var permissionDenied: some View {
        Section {
            RowLabel("Local Network access is off", symbol: "wifi.exclamationmark", symbolTint: theme.tint)
            Button("Open Settings", systemImage: "gear", action: openSettings)
        } footer: {
            Text("iFramed You talks to your frame over Wi-Fi only. Allow Local Network for iFramed You in Settings.")
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
    let flow: PairingFlow
    @State private var code = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    HStack(alignment: .top, spacing: Space.l) {
                        VStack(alignment: .leading, spacing: Space.s) {
                            Text("Enter the code on \(flow.frameName)").font(.hero)
                            Text("The frame shows a 6-digit code for two minutes. Only pair phones you trust.")
                                .font(.rowSubtitle)
                                .foregroundStyle(Theme.secondaryLabel)
                        }
                        FrameHero(width: 96)
                    }
                    VStack(spacing: Space.l) {
                        switch flow.step {
                        case .requestingCode, .idle:
                            ProgressView("Asking the frame for a code").frame(maxWidth: .infinity, minHeight: 56)
                        case .failed:
                            Image(systemName: "exclamationmark.triangle")
                                .font(.largeTitle)
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(theme.tint)
                        default:
                            CodeEntry(code: $code) { entered in
                                Task { await session.submit(code: entered) }
                            }
                            .disabled(flow.step == .verifying)
                            .opacity(flow.step == .verifying ? 0.5 : 1)
                        }
                        if flow.step == .verifying {
                            ProgressView("Checking")
                        }
                        if let message = flow.message {
                            Text(message).font(.note).foregroundStyle(theme.tint).multilineTextAlignment(.center)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    Button("Send a new code", systemImage: "arrow.clockwise") {
                        code = ""
                        Task { await flow.start() }
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .frame(maxWidth: .infinity)
                    .disabled(flow.step == .requestingCode || flow.step == .verifying)
                }
                .padding(Space.margin)
            }
            .background(theme.background.ignoresSafeArea())
            .navigationTitle("Pair with frame")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .sensoryFeedback(.error, trigger: flow.message) { _, new in new != nil }
        .onChange(of: flow.message) { _, message in
            if message != nil { code = "" }
        }
        .presentationDetents([.large])
    }
}
