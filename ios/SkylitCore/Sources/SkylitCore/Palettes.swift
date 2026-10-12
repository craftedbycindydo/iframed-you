import Foundation

public struct PaletteTokens: Equatable, Sendable {
    public let bg: String
    public let panel: String
    public let rail: String
    public let ink: String
    public let muted: String
    public let line: String
    public let accent: String
    public let accentInk: String
    public let soft: String

    init(_ values: [String]) {
        bg = values[0]
        panel = values[1]
        rail = values[2]
        ink = values[3]
        muted = values[4]
        line = values[5]
        accent = values[6]
        accentInk = values[7]
        soft = values[8]
    }
}

public struct Palette: Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let light: [String]
    public let dark: [String]

    public func tokens(dark isDark: Bool) -> PaletteTokens {
        PaletteTokens(isDark ? dark : light)
    }
}

public enum Palettes {
    public static let modes = ["auto", "light", "dark"]

    public static let all: [Palette] = [
        Palette(id: "linen", name: "Linen",
                light: ["#eee8dd", "#faf7f0", "#e4dccd", "#352e28", "#74695e", "#d8cfbf", "#9a513b", "#fff9f0", "#ead0b5"],
                dark: ["#241f1c", "#332d28", "#1c1917", "#f2e7d5", "#bdad98", "#51463b", "#e7b487", "#2c2018", "#554437"]),
        Palette(id: "sage", name: "Sage",
                light: ["#e4e8dd", "#f6f5ec", "#d5ddce", "#303b31", "#64705f", "#c7d0bf", "#526747", "#fffbee", "#dde2ca"],
                dark: ["#1d261e", "#29352a", "#172019", "#e4ebd8", "#a8b69f", "#46523f", "#adc68d", "#1c2c17", "#3a4934"]),
        Palette(id: "stone", name: "Stone",
                light: ["#e8e6e1", "#faf9f6", "#ddd9d2", "#383b37", "#6c7068", "#d0d0c9", "#5c6865", "#faf8f2", "#d6dfdc"],
                dark: ["#202423", "#2b302e", "#191d1c", "#e5e5dc", "#adb4aa", "#48514a", "#b1c5bd", "#20342b", "#3a4741"]),
        Palette(id: "ocean", name: "Ocean",
                light: ["#e4ebed", "#f5fafb", "#d5e0e3", "#344650", "#657b84", "#c5d4d9", "#44758a", "#f5fafb", "#d5e3e8"],
                dark: ["#1b272d", "#27353d", "#142128", "#deebee", "#a0b6c0", "#435863", "#95c1d1", "#18343f", "#354c59"]),
        Palette(id: "plum", name: "Plum",
                light: ["#ede4e8", "#fcf6f8", "#e3d5dc", "#493643", "#806b79", "#d7c8d1", "#8b5779", "#fff7fb", "#e7d4df"],
                dark: ["#2a2029", "#382d36", "#201820", "#ecdee7", "#bca4b3", "#574352", "#cc9cbb", "#3b2233", "#513b4c"]),
        Palette(id: "contrast", name: "High contrast",
                light: ["#f2efe7", "#ffffff", "#e3dfd4", "#171714", "#39392f", "#6f7062", "#353e29", "#ffffff", "#d5dfc7"],
                dark: ["#101310", "#191e19", "#080b08", "#ffffff", "#e0e8db", "#9aa994", "#d1eba9", "#17220c", "#34452a"]),
    ]

    public static let swatches = ["#9A513B", "#C98A3C", "#526747", "#00A36C", "#44758A", "#2D5BFF", "#8B5779", "#C0567A"]

    public static func palette(_ id: String) -> Palette {
        all.first { $0.id == id } ?? all[0]
    }

    public static func isDark(mode: String, systemDark: Bool) -> Bool {
        switch mode {
        case "dark": return true
        case "light": return false
        default: return systemDark
        }
    }
}
