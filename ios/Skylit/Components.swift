import SwiftUI
import SkylitCore

struct ThemedList<Content: View>: View {
    @Environment(\.theme) private var theme
    @ViewBuilder let content: Content

    var body: some View {
        List {
            content.listRowBackground(theme.groupedBackground)
        }
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 0, for: .scrollContent)
        .background(theme.background.ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
    }
}

struct ScreenHeader<Actions: View>: View {
    @Environment(\.theme) private var theme
    let title: String
    var status: String?
    var statusSymbol: String?
    @ViewBuilder let actions: Actions

    var body: some View {
        HStack(alignment: .top, spacing: Space.m) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(title)
                    .font(.screenTitle)
                    .lineLimit(1)
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .accessibilityAddTraits(.isHeader)
                if let status {
                    Label {
                        Text(status)
                    } icon: {
                        if let statusSymbol { Image(systemName: statusSymbol) }
                    }
                    .font(.status)
                    .foregroundStyle(Theme.secondaryLabel)
                    .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: Space.s) { actions }
                .fixedSize()
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .padding(.top, Space.xs)
        }
        .padding(.horizontal, Space.margin)
        .padding(.top, Space.xs)
        .padding(.bottom, Space.s)
        .frame(maxWidth: .infinity)
        .modifier(HeaderSurface())
    }
}

private struct HeaderSurface: ViewModifier {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(theme.background)
        } else {
            content.background(theme.background.opacity(0.85)).background(.ultraThinMaterial)
        }
    }
}

extension View {
    func screenHeader<Actions: View>(_ title: String, status: String? = nil, statusSymbol: String? = nil,
                                     @ViewBuilder actions: () -> Actions) -> some View {
        safeAreaInset(edge: .top, spacing: 0) {
            ScreenHeader(title: title, status: status, statusSymbol: statusSymbol, actions: actions)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    func screenHeader(_ title: String, status: String? = nil, statusSymbol: String? = nil) -> some View {
        screenHeader(title, status: status, statusSymbol: statusSymbol) { EmptyView() }
    }
}

extension FrameStore {
    var connectionStatus: String? {
        link == .offline ? "\(frame.name) · can't reach it right now" : nil
    }

    var connectionSymbol: String? {
        link == .offline ? "wifi.slash" : nil
    }
}

struct SectionHeader<Trailing: View>: View {
    let title: String
    var person: Person?
    var showsAvatar = false
    @ViewBuilder let trailing: Trailing

    init(_ title: String, person: Person? = nil, showsAvatar: Bool = false, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.person = person
        self.showsAvatar = showsAvatar
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: Space.s) {
            if showsAvatar { Avatar(person: person, size: 20) }
            Text(title).foregroundStyle(Theme.secondaryLabel)
            Spacer(minLength: Space.s)
            trailing
        }
        .font(.sectionTitle)
        .textCase(nil)
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(_ title: String, person: Person? = nil, showsAvatar: Bool = false) {
        self.init(title, person: person, showsAvatar: showsAvatar) { EmptyView() }
    }
}

extension SectionHeader where Trailing == Text {
    init(_ title: String, person: Person? = nil, showsAvatar: Bool = false, count: String) {
        self.init(title, person: person, showsAvatar: showsAvatar) { Text(count).monospacedDigit().foregroundStyle(Theme.secondaryLabel) }
    }
}

struct RowLabel<Leading: View, Trailing: View>: View {
    @ScaledMetric(relativeTo: .title2) private var glyph = Size.glyph
    @Environment(\.dynamicTypeSize) private var typeSize
    let title: String
    var subtitle: String?
    var emoji: String?
    var symbol: String?
    var symbolTint: Color?
    var isDimmed = false
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    var body: some View {
        let body = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Space.xs))
            : AnyLayout(HStackLayout(spacing: Space.m))
        HStack(spacing: Space.m) {
            leading
            body {
                if let emoji {
                    Group {
                        if emoji.isEmpty {
                            Image(systemName: "sparkle").foregroundStyle(Theme.tertiaryLabel)
                        } else {
                            Text(emoji).font(.control)
                        }
                    }
                    .frame(width: glyph, height: glyph)
                    .accessibilityHidden(true)
                } else if let symbol {
                    Image(systemName: symbol)
                        .font(.glyph)
                        .foregroundStyle(symbolTint ?? Theme.label)
                        .frame(width: glyph, height: glyph)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text(title)
                        .font(.rowTitle)
                        .foregroundStyle(isDimmed ? Theme.secondaryLabel : Theme.label)
                        .strikethrough(isDimmed)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle).font(.rowSubtitle).foregroundStyle(Theme.secondaryLabel)
                    }
                }
                .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
            trailing
        }
    }
}

extension RowLabel where Leading == EmptyView, Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil, emoji: String? = nil, symbol: String? = nil, symbolTint: Color? = nil, isDimmed: Bool = false) {
        self.init(title: title, subtitle: subtitle, emoji: emoji, symbol: symbol, symbolTint: symbolTint, isDimmed: isDimmed,
                  leading: { EmptyView() }, trailing: { EmptyView() })
    }
}

extension RowLabel where Leading == EmptyView {
    init(_ title: String, subtitle: String? = nil, emoji: String? = nil, symbol: String? = nil, symbolTint: Color? = nil,
         isDimmed: Bool = false, @ViewBuilder trailing: () -> Trailing) {
        self.init(title: title, subtitle: subtitle, emoji: emoji, symbol: symbol, symbolTint: symbolTint, isDimmed: isDimmed,
                  leading: { EmptyView() }, trailing: trailing)
    }
}

struct RowValue: View {
    let text: String

    var body: some View {
        Text(text).font(.rowValue).foregroundStyle(Theme.secondaryLabel).monospacedDigit()
    }
}

struct RowDisclosure: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let isExpanded: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            Image(systemName: "chevron.down")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.tertiaryLabel)
                .rotationEffect(.degrees(isExpanded ? 0 : -90))
                .animation(reduceMotion ? nil : Motion.state, value: isExpanded)
                .frame(width: Size.touch, height: Size.touch)
                .contentShape(Rectangle())
        }
        .buttonStyle(RowButtonStyle())
        .accessibilityLabel("Details")
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
        .accessibilityHint(isExpanded ? "Hides the editing controls" : "Shows the editing controls")
    }
}

struct InlineEditorRow: ViewModifier {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .listRowBackground(theme.fill.opacity(0.4).background(theme.groupedBackground))
            .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
    }
}

extension View {
    func inlineEditorRow() -> some View {
        modifier(InlineEditorRow())
    }
}

struct RowChevron: View {
    var body: some View {
        Image(systemName: "chevron.forward")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.tertiaryLabel)
            .accessibilityHidden(true)
    }
}

struct TickButton: View {
    @Environment(\.theme) private var theme
    @ScaledMetric(relativeTo: .title2) private var size = Size.control
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "checkmark.circle.fill")
                .font(.control)
                .foregroundStyle(theme.tint)
                .frame(width: max(Size.touch, size), height: max(Size.touch, size))
        }
        .buttonStyle(RowButtonStyle())
        .accessibilityLabel(label)
    }
}

struct DoneMark: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title2) private var size = Size.control
    let isOn: Bool
    var tint: Color?

    var body: some View {
        let mark = Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
            .font(.control)
            .foregroundStyle(isOn ? (tint ?? theme.tint) : Theme.tertiaryLabel)
        Group {
            if reduceMotion {
                mark
            } else {
                mark
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: isOn)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct ProgressSummary: View {
    @Environment(\.theme) private var theme
    let done: Int
    let total: Int
    let caption: String
    let headline: String

    var body: some View {
        HStack(spacing: Space.l) {
            Gauge(value: total == 0 ? 0 : Double(done) / Double(total)) {
                Text("Done")
            } currentValueLabel: {
                Text("\(done)/\(total)").font(.caption.weight(.semibold)).monospacedDigit()
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(theme.tint)
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(caption).font(.rowSubtitle).foregroundStyle(Theme.secondaryLabel)
                Text(headline).font(.hero)
            }
        }
        .padding(.vertical, Space.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(done) of \(total) done. \(headline)")
    }
}

struct InlineAddField: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title2) private var size = Size.control
    let prompt: String
    @Binding var text: String
    var focus: FocusState<Bool>.Binding
    let limit: Int
    let onSubmit: () -> Void

    private var hasText: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        HStack(spacing: Space.m) {
            Button {
                focus.wrappedValue = true
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.control)
                    .foregroundStyle(theme.tint)
                    .frame(width: size, height: size)
            }
            .buttonStyle(RowButtonStyle())
            .accessibilityHidden(true)
            TextField(prompt, text: $text)
                .touchTarget()
                .onTapGesture { focus.wrappedValue = true }
                .focused(focus)
                .submitLabel(.next)
                .onSubmit {
                    if hasText { onSubmit() } else { focus.wrappedValue = false }
                }
                .onChange(of: text) { _, new in
                    if Limits.clipped(new, to: limit) != new { text = Limits.clipped(new, to: limit) }
                }
            if hasText {
                TickButton(label: prompt, action: onSubmit)
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .stateAnimation(hasText)
    }
}

struct Avatar: View {
    @Environment(\.theme) private var theme
    let person: Person?
    var size: CGFloat = Size.avatar

    var body: some View {
        ZStack {
            Circle().fill(person.map { Color(hex: $0.color) } ?? theme.fill)
            if let person {
                Text(String(person.name.prefix(1)).uppercased())
                    .font(.system(size: size * 0.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            } else {
                Image(systemName: "person.2.fill")
                    .font(.system(size: size * 0.42))
                    .foregroundStyle(theme.mutedFigure)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct SwatchPicker: View {
    @Binding var selection: String

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 4), spacing: 0) {
            ForEach(Palettes.swatches, id: \.self) { hex in
                let isSelected = hex.caseInsensitiveCompare(selection) == .orderedSame
                Button {
                    selection = hex
                } label: {
                    Circle().fill(Color(hex: hex))
                        .frame(width: Size.control, height: Size.control)
                        .overlay {
                            Image(systemName: "checkmark")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                                .opacity(isSelected ? 1 : 0)
                        }
                        .frame(maxWidth: .infinity, minHeight: Size.touch)
                        .contentShape(Rectangle())
                }
                .buttonStyle(RowButtonStyle())
                .accessibilityLabel(Palettes.swatchName(hex))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .stateAnimation(selection)
    }
}

struct PaletteGrid: View {
    @Environment(\.theme) private var theme
    let selected: String
    let onSelect: (String) -> Void

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Space.m), count: 3), spacing: Space.m) {
            ForEach(Palettes.all) { palette in
                let isSelected = selected == palette.id
                let sample = Theme(palette: palette.id, dark: theme.isDark)
                Button {
                    onSelect(palette.id)
                } label: {
                    VStack(spacing: Space.s) {
                        HStack(spacing: Space.xs) {
                            RoundedRectangle(cornerRadius: Space.xs, style: .continuous).fill(sample.groupedBackground)
                            RoundedRectangle(cornerRadius: Space.xs, style: .continuous).fill(sample.tint)
                            RoundedRectangle(cornerRadius: Space.xs, style: .continuous).fill(sample.fill)
                        }
                        .padding(Space.s)
                        .frame(height: 40)
                        .background(sample.background, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                            .strokeBorder(isSelected ? theme.tint : Theme.separator, lineWidth: isSelected ? 2 : 1))
                        Text(palette.name)
                            .font(.caption)
                            .foregroundStyle(isSelected ? Theme.label : Theme.secondaryLabel)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                .buttonStyle(RowButtonStyle())
                .accessibilityLabel(palette.name)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(.vertical, Space.xs)
        .stateAnimation(selected)
    }
}

struct CodeEntry: View {
    @Environment(\.theme) private var theme
    @Binding var code: String
    var onComplete: (String) -> Void

    @FocusState private var focused: Bool
    private let count = PairingFlow.codeLength
    #if DEBUG
    @MainActor static var trace = ""
    #endif

    var body: some View {
        ZStack {
            TextField("", text: $code)
                .textContentType(.oneTimeCode)
                .keyboardType(.numberPad)
                .focused($focused)
                .opacity(0.02)
                .onChange(of: code) { old, new in
                    let clean = PairingFlow.asciiDigits(new)
                    if clean != new { code = clean }
                    let fires = clean.count == count && old.count < count
                    #if DEBUG
                    Self.trace += "\(old.count)>\(new.count)\(fires ? "!" : "") "
                    #endif
                    if fires { onComplete(clean) }
                }
                .accessibilityLabel("Pairing code")
                .accessibilityValue(traceValue)
            HStack(spacing: Space.s) {
                ForEach(0..<count, id: \.self) { index in
                    let isCurrent = index == code.count
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .fill(theme.groupedBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                                .strokeBorder(isCurrent ? theme.tint : Theme.separator, lineWidth: isCurrent ? 2 : 1)
                        )
                        .overlay(Text(digit(index)).font(.hero))
                        .frame(maxWidth: 48)
                        .frame(height: 56)
                }
            }
            .environment(\.layoutDirection, .leftToRight)
            .contentShape(Rectangle())
            .onTapGesture { focused = true }
            .accessibilityHidden(true)
        }
        .stateAnimation(code)
        .task {
            try? await Task.sleep(for: .milliseconds(450))
            focused = true
        }
    }

    private var traceValue: String {
        #if DEBUG
        return "\(code) [\(Self.trace)]"
        #else
        return code
        #endif
    }

    private func digit(_ index: Int) -> String {
        index < code.count ? String(Array(code)[index]) : ""
    }
}

struct EditorToolbar: ViewModifier {
    @Environment(\.dismiss) private var dismiss
    let confirmLabel: String
    let canConfirm: Bool
    let onConfirm: () -> Void

    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
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

extension View {
    func editorToolbar(_ confirmLabel: String = "Save", canConfirm: Bool, onConfirm: @escaping () -> Void) -> some View {
        modifier(EditorToolbar(confirmLabel: confirmLabel, canConfirm: canConfirm, onConfirm: onConfirm))
    }
}

struct NoticeToast: View {
    @Binding var notice: String?
    var actionLabel: String?
    var action: (() -> Void)?

    var body: some View {
        if let text = notice {
            HStack(spacing: Space.m) {
                Text(text).font(.note).multilineTextAlignment(.leading)
                if let actionLabel {
                    Button(actionLabel) {
                        action?()
                        notice = nil
                    }
                    .font(.note.weight(.semibold))
                }
            }
            .padding(.horizontal, Space.l)
            .padding(.vertical, Space.m)
            .modifier(GlassSurface())
            .padding(.horizontal, Space.margin)
            .transition(.opacity)
            .onTapGesture { if actionLabel == nil { notice = nil } }
            .task(id: text) {
                try? await Task.sleep(for: .seconds(actionLabel == nil ? 4 : 6))
                if !Task.isCancelled { notice = nil }
            }
        }
    }
}

struct GlassSurface: ViewModifier {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(theme.groupedBackground, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.separator))
        } else if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: Capsule())
        } else {
            content.background(.regularMaterial, in: Capsule())
        }
    }
}

struct FrameHero: View {
    @Environment(\.theme) private var theme
    var width: CGFloat = 200

    var body: some View {
        Canvas { context, size in
            let h = size.height
            let unit = h / 1024
            func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ hh: CGFloat) -> CGRect {
                CGRect(x: x * unit, y: y * unit, width: w * unit, height: hh * unit)
            }
            var wire = Path()
            wire.move(to: CGPoint(x: 290 * unit, y: 404 * unit))
            wire.addLine(to: CGPoint(x: 512 * unit, y: 104 * unit))
            wire.addLine(to: CGPoint(x: 734 * unit, y: 404 * unit))
            context.stroke(wire, with: .color(theme.inkFigure), style: StrokeStyle(lineWidth: 40 * unit, lineCap: .round, lineJoin: .round))
            context.fill(Path(ellipseIn: rect(468, 60, 88, 88)), with: .color(theme.inkFigure))
            context.fill(Path(roundedRect: rect(196, 362, 632, 600), cornerRadius: 60 * unit), with: .color(theme.tint))
            context.fill(Path(roundedRect: rect(252, 418, 520, 488), cornerRadius: 28 * unit), with: .color(theme.groupedBackground))
            let photo = Path(roundedRect: rect(316, 482, 392, 360), cornerRadius: 20 * unit)
            context.fill(photo, with: .color(theme.fill))
            context.drawLayer { layer in
                layer.clip(to: photo)
                for (cx, cy, r, color) in [(430.0, 600.0, 66.0, theme.tint), (560.0, 572.0, 76.0, theme.inkFigure), (640.0, 690.0, 46.0, theme.mutedFigure)] {
                    layer.fill(Path(ellipseIn: rect(cx - r, cy - r, r * 2, r * 2)), with: .color(color))
                    layer.fill(Path(roundedRect: rect(cx - r * 1.23, cy + r * 0.9, r * 2.46, 400), cornerRadius: r * 1.23 * unit), with: .color(color))
                }
            }

            let phone = rect(1180, 330, 300, 760)
            context.fill(Path(roundedRect: phone, cornerRadius: 56 * unit), with: .color(theme.inkFigure))
            let screen = phone.insetBy(dx: 22 * unit, dy: 26 * unit)
            context.fill(Path(roundedRect: screen, cornerRadius: 40 * unit), with: .color(theme.groupedBackground))
            let tile = CGRect(x: screen.minX + screen.width * 0.16, y: screen.minY + screen.height * 0.12,
                              width: screen.width * 0.68, height: screen.height * 0.24)
            context.fill(Path(roundedRect: tile, cornerRadius: 16 * unit), with: .color(theme.tint))
            for row in 0..<3 {
                let line = CGRect(x: tile.minX, y: tile.maxY + screen.height * (0.11 + Double(row) * 0.14),
                                  width: tile.width * (row == 1 ? 0.6 : 0.9), height: screen.height * 0.055)
                context.fill(Path(roundedRect: line, cornerRadius: line.height / 2), with: .color(theme.fill))
            }
            let origin = CGPoint(x: phone.minX - 40 * unit, y: phone.minY + phone.height * 0.24)
            for (index, radius) in [80.0, 150.0, 220.0].enumerated() {
                var arc = Path()
                arc.addArc(center: origin, radius: radius * unit, startAngle: .degrees(150), endAngle: .degrees(210), clockwise: false)
                context.stroke(arc, with: .color(theme.tint.opacity(1 - Double(index) * 0.28)),
                               style: StrokeStyle(lineWidth: 34 * unit, lineCap: .round))
            }
        }
        .frame(width: width, height: width * 1024 / 1500)
        .accessibilityHidden(true)
    }
}
