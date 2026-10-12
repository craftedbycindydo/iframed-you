import SwiftUI
import SkylitCore

struct Theme: Equatable {
    let background: Color
    let groupedBackground: Color
    let fill: Color
    let tint: Color
    let onTint: Color
    let inkFigure: Color
    let mutedFigure: Color
    let isDark: Bool

    static let label = Color.primary
    static let secondaryLabel = Color.secondary
    static let tertiaryLabel = Color(.tertiaryLabel)
    static let separator = Color(.separator)
    static let destructive = Color.red
    static let connected = Color.green
    static let heating = Color.orange
    static let cooling = Color.blue

    init(palette: String = "linen", dark: Bool) {
        let tokens = Palettes.palette(palette).tokens(dark: dark)
        background = Color(hex: tokens.bg)
        groupedBackground = Color(hex: tokens.panel)
        fill = Color(hex: tokens.soft)
        tint = Color(hex: tokens.accent)
        onTint = Color(hex: tokens.accentInk)
        inkFigure = Color(hex: tokens.ink)
        mutedFigure = Color(hex: tokens.muted)
        isDark = dark
    }

    init(appearance: FrameAppearance, systemDark: Bool) {
        self.init(palette: appearance.palette, dark: Palettes.isDark(mode: appearance.mode, systemDark: systemDark))
    }
}

extension Color {
    init(hex: String) {
        let value = UInt32(hex.dropFirst(), radix: 16) ?? 0x888888
        self.init(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme(dark: false)
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

enum Space {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let margin: CGFloat = 16
}

enum Radius {
    static var container: CGFloat {
        if #available(iOS 26.0, *) { return 26 }
        return 10
    }

    static let control: CGFloat = 10
}

enum Size {
    static let control: CGFloat = 28
    static let glyph: CGFloat = 28
    static let avatar: CGFloat = 28
    static let touch: CGFloat = 44
}

extension Font {
    static let screenTitle = Font.system(.largeTitle, design: .serif, weight: .bold)
    static let hero = Font.system(.title2, design: .serif, weight: .semibold)
    static let figure = Font.system(.title2, weight: .semibold)
    static let sectionTitle = Font.subheadline
    static let rowTitle = Font.body
    static let rowSubtitle = Font.subheadline
    static let rowValue = Font.body
    static let status = Font.subheadline
    static let note = Font.footnote
}

enum Motion {
    static let state = Animation.spring(response: 0.35, dampingFraction: 1)
    static let gesture = Animation.spring(response: 0.35, dampingFraction: 0.8)
    static let reduced = Animation.easeOut(duration: 0.15)
}

struct StateAnimation<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let value: Value

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? Motion.reduced : Motion.state, value: value)
    }
}

extension View {
    func stateAnimation<Value: Equatable>(_ value: Value) -> some View {
        modifier(StateAnimation(value: value))
    }
}

struct RowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.5 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct HeaderActionStyle: ViewModifier {
    let prominent: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            if prominent { content.buttonStyle(.glassProminent) } else { content.buttonStyle(.glass) }
        } else {
            if prominent { content.buttonStyle(.borderedProminent) } else { content.buttonStyle(.bordered) }
        }
    }
}

extension View {
    func headerAction(prominent: Bool = false) -> some View {
        modifier(HeaderActionStyle(prominent: prominent))
            .labelStyle(.iconOnly)
            .controlSize(.large)
            .buttonBorderShape(.circle)
    }
}
