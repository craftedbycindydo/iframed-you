import SwiftUI
import SkylitCore

struct Card<Content: View>: View {
    @Environment(\.theme) private var theme
    var padding: CGFloat = 18
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.panel, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous).strokeBorder(theme.line, lineWidth: 1))
    }
}

struct Eyebrow: View {
    @Environment(\.theme) private var theme
    let text: String

    var body: some View {
        Text(text.uppercased()).textStyle(.eyebrow).foregroundStyle(theme.muted)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .textStyle(.label)
            .foregroundStyle(theme.accentInk)
            .frame(maxWidth: .infinity, minHeight: Metrics.controlHeight)
            .padding(.horizontal, 18)
            .background(theme.accent, in: RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(Motion.settle, value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    var destructive = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .textStyle(.label)
            .foregroundStyle(destructive ? theme.accent : theme.ink)
            .frame(maxWidth: .infinity, minHeight: Metrics.controlHeight)
            .padding(.horizontal, 18)
            .background(theme.soft, in: RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.45)
            .animation(Motion.settle, value: configuration.isPressed)
    }
}

struct IconButton: View {
    @Environment(\.theme) private var theme
    let symbol: String
    let label: String
    var filled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(filled ? theme.accentInk : theme.ink)
                .frame(width: Metrics.touch, height: Metrics.touch)
                .background(filled ? theme.accent : theme.soft, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

struct FieldStyle: ViewModifier {
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        content
            .textStyle(.body)
            .foregroundStyle(theme.ink)
            .tint(theme.accent)
            .padding(.horizontal, 14)
            .frame(minHeight: Metrics.controlHeight)
            .background(theme.bg, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(theme.line, lineWidth: 1))
    }
}

extension View {
    func fieldStyle() -> some View {
        modifier(FieldStyle())
    }
}

struct FieldLabel: View {
    @Environment(\.theme) private var theme
    let text: String

    var body: some View {
        Text(text).textStyle(.caption).foregroundStyle(theme.muted)
    }
}

struct Avatar: View {
    @Environment(\.theme) private var theme
    let person: Person?
    var size: CGFloat = 36

    var body: some View {
        ZStack {
            Circle().fill(person.map { Color(hex: $0.color) } ?? theme.soft)
            if let person {
                Text(String(person.name.prefix(1)).uppercased())
                    .font(.system(size: size * 0.44, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            } else {
                Image(systemName: "person.2.fill")
                    .font(.system(size: size * 0.36))
                    .foregroundStyle(theme.muted)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct CheckCircle: View {
    @Environment(\.theme) private var theme
    let isOn: Bool
    var tint: Color?

    var body: some View {
        ZStack {
            Circle().strokeBorder(isOn ? Color.clear : theme.line, lineWidth: 2)
            Circle().fill(tint ?? theme.accent).scaleEffect(isOn ? 1 : 0.01).opacity(isOn ? 1 : 0)
            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(tint == nil ? theme.accentInk : .white)
                .scaleEffect(isOn ? 1 : 0.4)
                .opacity(isOn ? 1 : 0)
        }
        .frame(width: 28, height: 28)
        .animation(Motion.pop, value: isOn)
    }
}

struct ProgressRing: View {
    @Environment(\.theme) private var theme
    let progress: Double
    let label: String

    var body: some View {
        ZStack {
            Circle().stroke(theme.soft, lineWidth: 8)
            Circle().trim(from: 0, to: progress)
                .stroke(theme.accent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(Motion.settle, value: progress)
            Text(label).textStyle(.heading).foregroundStyle(theme.ink).monospacedDigit()
        }
        .frame(width: 76, height: 76)
        .accessibilityHidden(true)
    }
}

struct SwatchPicker: View {
    @Environment(\.theme) private var theme
    @Binding var selection: String

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 8), spacing: 8) {
            ForEach(Palettes.swatches, id: \.self) { hex in
                let isSelected = hex.caseInsensitiveCompare(selection) == .orderedSame
                Button {
                    selection = hex
                } label: {
                    Circle().fill(Color(hex: hex))
                        .frame(width: 30, height: 30)
                        .padding(4)
                        .overlay(Circle().strokeBorder(isSelected ? theme.ink : .clear, lineWidth: 2))
                        .frame(maxWidth: .infinity, minHeight: Metrics.touch)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Colour \(hex)")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}

struct CodeEntry: View {
    @Environment(\.theme) private var theme
    @Binding var code: String
    var onComplete: (String) -> Void

    @FocusState private var focused: Bool
    private let count = PairingFlow.codeLength

    var body: some View {
        ZStack {
            TextField("", text: $code)
                .textContentType(.oneTimeCode)
                .keyboardType(.numberPad)
                .focused($focused)
                .opacity(0.02)
                .onChange(of: code) { old, new in
                    let clean = String(new.filter { $0.isASCII && $0.isNumber }.prefix(count))
                    if clean != new { code = clean }
                    if clean.count == count, old.count < count { onComplete(clean) }
                }
                .accessibilityLabel("Pairing code")
            HStack(spacing: 8) {
                ForEach(0..<count, id: \.self) { index in
                    let isCurrent = index == code.count
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(theme.bg)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(isCurrent ? theme.accent : theme.line, lineWidth: isCurrent ? 2 : 1)
                        )
                        .overlay(
                            Text(digit(index))
                                .font(.custom("Georgia", size: 28))
                                .foregroundStyle(theme.ink)
                        )
                        .frame(maxWidth: 48)
                        .frame(height: 58)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { focused = true }
            .accessibilityHidden(true)
        }
        .animation(Motion.fade, value: code)
        .task {
            try? await Task.sleep(for: .milliseconds(450))
            focused = true
        }
    }

    private func digit(_ index: Int) -> String {
        index < code.count ? String(Array(code)[index]) : ""
    }
}

struct Screen<Trailing: View, Content: View>: View {
    @Environment(\.theme) private var theme
    let title: String
    let store: FrameStore
    @ViewBuilder let trailing: Trailing
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.gap) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 7) {
                            Circle().fill(store.link == .offline ? theme.muted : Color(hex: "#6B9B6A")).frame(width: 7, height: 7)
                            Eyebrow(text: store.link == .offline ? "\(store.frame.name) · offline" : store.frame.name)
                        }
                        Text(title).textStyle(.display).foregroundStyle(theme.ink)
                    }
                    Spacer(minLength: 12)
                    HStack(spacing: 10) { trailing }
                }
                .padding(.top, 8)
                if store.link == .offline {
                    Card(padding: 14) {
                        Label("Can't reach the frame right now. Changes will work again when it is back on this Wi-Fi.", systemImage: "wifi.slash")
                            .textStyle(.caption)
                            .foregroundStyle(theme.muted)
                    }
                }
                content
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.bottom, 32)
        }
        .background(theme.bg.ignoresSafeArea())
        .refreshable { await store.refresh() }
        .scrollDismissesKeyboard(.interactively)
    }
}

struct SheetScaffold<Content: View>: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    let title: String
    var confirmLabel = "Save"
    var dismissLabel: String?
    var canConfirm = true
    var onConfirm: (() -> Void)?
    @ViewBuilder let content: Content

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.gap) { content }
                    .padding(Metrics.gutter)
            }
            .background(theme.bg.ignoresSafeArea())
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(dismissLabel ?? (onConfirm == nil ? "Done" : "Cancel")) { dismiss() }
                }
                if let onConfirm {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(confirmLabel) {
                            onConfirm()
                            dismiss()
                        }
                        .fontWeight(.semibold)
                        .disabled(!canConfirm)
                    }
                }
            }
        }
        .tint(theme.accent)
    }
}

struct NoticeToast: View {
    @Environment(\.theme) private var theme
    @Binding var notice: String?

    var body: some View {
        if let text = notice {
            Text(text)
                .textStyle(.caption)
                .foregroundStyle(theme.panel)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 18)
                .padding(.vertical, 13)
                .background(theme.ink, in: RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous))
                .padding(.horizontal, Metrics.gutter)
                .padding(.bottom, 12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .onTapGesture { notice = nil }
                .task(id: text) {
                    try? await Task.sleep(for: .seconds(4))
                    if !Task.isCancelled { notice = nil }
                }
                .accessibilityAddTraits(.isStaticText)
        }
    }
}

struct SunMark: View {
    @Environment(\.theme) private var theme
    var size: CGFloat = 64

    var body: some View {
        ZStack {
            Circle().fill(theme.accent.opacity(0.10))
            Circle().fill(theme.accent.opacity(0.18)).padding(size * 0.12)
            Circle().fill(theme.accent).padding(size * 0.26)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
