import SwiftUI
import SkylitCore

struct Theme: Equatable {
    let bg: Color
    let panel: Color
    let rail: Color
    let ink: Color
    let muted: Color
    let line: Color
    let accent: Color
    let accentInk: Color
    let soft: Color
    let isDark: Bool

    init(palette: String = "linen", dark: Bool) {
        let tokens = Palettes.palette(palette).tokens(dark: dark)
        bg = Color(hex: tokens.bg)
        panel = Color(hex: tokens.panel)
        rail = Color(hex: tokens.rail)
        ink = Color(hex: tokens.ink)
        muted = Color(hex: tokens.muted)
        line = Color(hex: tokens.line)
        accent = Color(hex: tokens.accent)
        accentInk = Color(hex: tokens.accentInk)
        soft = Color(hex: tokens.soft)
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

enum Metrics {
    static let gutter: CGFloat = 20
    static let gap: CGFloat = 16
    static let cardRadius: CGFloat = 18
    static let controlRadius: CGFloat = 13
    static let controlHeight: CGFloat = 50
    static let touch: CGFloat = 44
}

enum Motion {
    static let settle = Animation.spring(response: 0.4, dampingFraction: 1)
    static let pop = Animation.spring(response: 0.35, dampingFraction: 0.7)
    static let fade = Animation.easeOut(duration: 0.2)
}

enum TextStyle {
    case display
    case title
    case heading
    case body
    case label
    case caption
    case eyebrow

    var font: Font {
        switch self {
        case .display: return .custom("Georgia", size: 38, relativeTo: .largeTitle)
        case .title: return .custom("Georgia", size: 26, relativeTo: .title)
        case .heading: return .custom("Georgia", size: 21, relativeTo: .title3)
        case .body: return .system(.body)
        case .label: return .system(.subheadline, weight: .semibold)
        case .caption: return .system(.footnote)
        case .eyebrow: return .system(.caption2, weight: .semibold)
        }
    }

    var tracking: CGFloat {
        switch self {
        case .display: return -0.9
        case .title: return -0.5
        case .heading: return -0.3
        case .eyebrow: return 1.3
        default: return 0
        }
    }
}

extension View {
    func textStyle(_ style: TextStyle) -> some View {
        font(style.font).tracking(style.tracking)
    }
}
