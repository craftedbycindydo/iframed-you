import SwiftUI
import SkylitCore

struct ConnectScreen: View {
    @Environment(FrameSession.self) private var session
    @Environment(\.theme) private var theme
    @Environment(\.openURL) private var openURL
    @State private var manualAddress = ""
    @State private var showsManual = false
    @State private var hasWaited = false

    var body: some View {
        @Bindable var session = session
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.gap) {
                header
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
            .padding(.horizontal, Metrics.gutter)
            .padding(.bottom, 32)
        }
        .background(theme.bg.ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
        .overlay(alignment: .bottom) {
            NoticeToast(notice: $session.notice).animation(Motion.settle, value: session.notice)
        }
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            SunMark()
            Text("Skylit").textStyle(.display).foregroundStyle(theme.ink)
            Text(session.paired == nil ? "Find your frame on this Wi-Fi to manage chores, shopping, photos and setup."
                 : "Getting back in touch with your frame.")
                .textStyle(.body)
                .foregroundStyle(theme.muted)
        }
        .padding(.top, 36)
        .padding(.bottom, 8)
    }

    private func reconnecting(_ paired: PairedFrame) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    ProgressView().tint(theme.accent)
                    Text("Looking for \(paired.name)").textStyle(.heading).foregroundStyle(theme.ink)
                }
                Text(session.discovery == .permissionDenied
                     ? "Skylit isn't allowed to look for devices on your network. Turn on Local Network for Skylit in Settings."
                     : "Make sure the frame is switched on and this phone is on the same Wi-Fi. This screen updates by itself.")
                    .textStyle(.caption)
                    .foregroundStyle(theme.muted)
                if session.discovery == .permissionDenied {
                    Button("Open Settings", action: openSettings).buttonStyle(PrimaryButtonStyle())
                }
                Button("Use a different frame") { session.leave() }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    @ViewBuilder private var frames: some View {
        Eyebrow(text: "Frames nearby").padding(.top, 4)
        if session.frames.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        ProgressView().tint(theme.accent)
                        Text(hasWaited ? "No frame found yet" : "Searching").textStyle(.heading).foregroundStyle(theme.ink)
                    }
                    if hasWaited {
                        Text("Check that the frame is on, that it is running Skylit, and that this phone is on the same Wi-Fi. Guest networks often keep devices apart.")
                            .textStyle(.caption)
                            .foregroundStyle(theme.muted)
                    }
                }
            }
        } else {
            Card(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(session.frames.enumerated()), id: \.element.id) { index, frame in
                        if index > 0 { Divider().overlay(theme.line).padding(.leading, 66) }
                        Button {
                            Task { await session.select(frame) }
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "photo.tv")
                                    .font(.system(size: 17, weight: .medium))
                                    .foregroundStyle(theme.accent)
                                    .frame(width: 36, height: 36)
                                    .background(theme.soft, in: Circle())
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(frame.name).textStyle(.body).foregroundStyle(theme.ink)
                                    Text(session.hasToken(for: frame) ? "Paired with this phone" : "Tap to pair")
                                        .textStyle(.caption)
                                        .foregroundStyle(theme.muted)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(theme.muted)
                            }
                            .padding(.horizontal, 16)
                            .frame(minHeight: 68)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(session.isBusy)
                    }
                }
            }
        }
    }

    private var permissionDenied: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                Label("Local Network access is off", systemImage: "wifi.exclamationmark")
                    .textStyle(.heading)
                    .foregroundStyle(theme.ink)
                Text("Skylit talks to your frame directly over Wi-Fi and never through the internet. Allow Local Network for Skylit in Settings, then come back.")
                    .textStyle(.caption)
                    .foregroundStyle(theme.muted)
                Button("Open Settings", action: openSettings).buttonStyle(PrimaryButtonStyle())
            }
        }
    }

    private func browseFailed(_ reason: String) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Label("Can't search this network", systemImage: "wifi.slash").textStyle(.heading).foregroundStyle(theme.ink)
                Text("Connect this phone to Wi-Fi, or enter the frame's address below. (\(reason))")
                    .textStyle(.caption)
                    .foregroundStyle(theme.muted)
            }
        }
    }

    private var manualEntry: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(Motion.settle) { showsManual.toggle() }
            } label: {
                HStack {
                    Text("Enter the frame's address instead").textStyle(.label)
                    Image(systemName: "chevron.down").font(.footnote.weight(.semibold)).rotationEffect(.degrees(showsManual ? 180 : 0))
                }
                .foregroundStyle(theme.muted)
                .frame(minHeight: Metrics.touch)
            }
            .buttonStyle(.plain)
            if showsManual {
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        FieldLabel(text: "Shown on the frame under Settings › Phone")
                        TextField("192.168.1.20:8765", text: $manualAddress)
                            .keyboardType(.numbersAndPunctuation)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.go)
                            .onSubmit(connectManually)
                            .fieldStyle()
                        Button(action: connectManually) {
                            if session.isBusy { ProgressView().tint(theme.accentInk) } else { Text("Connect") }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(session.isBusy || manualAddress.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func connectManually() {
        Task { await session.connect(manualAddress: manualAddress) }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
    }
}

struct PairingSheet: View {
    @Environment(FrameSession.self) private var session
    @Environment(\.theme) private var theme
    let flow: PairingFlow
    @State private var code = ""

    var body: some View {
        SheetScaffold(title: "Pair with frame", dismissLabel: "Cancel") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Enter the code on \(flow.frameName)").textStyle(.title).foregroundStyle(theme.ink)
                Text("The frame is showing a 6-digit code for two minutes. Anyone holding this code can manage the frame, so only pair phones you trust.")
                    .textStyle(.caption)
                    .foregroundStyle(theme.muted)
            }
            Card {
                VStack(spacing: 16) {
                    switch flow.step {
                    case .requestingCode, .idle:
                        ProgressView("Asking the frame for a code").tint(theme.accent).frame(maxWidth: .infinity, minHeight: 58)
                    case .failed:
                        Image(systemName: "exclamationmark.circle").font(.title).foregroundStyle(theme.accent)
                    default:
                        CodeEntry(code: $code) { entered in
                            Task { await session.submit(code: entered) }
                        }
                        .disabled(flow.step == .verifying)
                        .opacity(flow.step == .verifying ? 0.5 : 1)
                    }
                    if flow.step == .verifying {
                        ProgressView("Checking").tint(theme.accent)
                    }
                    if let message = flow.message {
                        Text(message).textStyle(.caption).foregroundStyle(theme.accent).multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            Button("Send a new code") {
                code = ""
                Task { await flow.start() }
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(flow.step == .requestingCode || flow.step == .verifying)
        }
        .onChange(of: flow.message) { _, message in
            if message != nil { code = "" }
        }
        .presentationDetents([.large])
    }
}
