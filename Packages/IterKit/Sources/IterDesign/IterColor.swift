import SwiftUI
import IterCore
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Colours by role. Every value is read from `TokenValues`; nothing here is a literal.
/// Semantic UI colours (text, separator, backgrounds) are system colours; brand and data colours are concrete.
public enum IterColor {
    // Interface
    public static let accent = make("accent/primary")
    public static let accentText = make("accent/text")
    public static let onAccent = make("accent/onAccent")
    public static let focusRing = make("focus/ring")
    // Journey
    public static let route = make("route/active")
    public static let routeInactive = make("route/inactive")
    // Light moment
    public static let brandDot = make("brand/dot")
    public static let sun = make("map/sun")
    public static let moon = make("map/moon")
    // Status (always with an icon)
    public static let warning = make("status/warning")
    public static let danger = make("status/danger")
    public static let noForecast = make("status/noForecast")
    // Sky bands for the timeline
    public static let skyNight = make("sky/night")
    public static let skyBlue = make("sky/blueHour")
    public static let skyGolden = make("sky/golden")
    public static let skyDay = make("sky/day")
    // Cloud layers
    public static let cloudLow = make("cloud/low")
    public static let cloudMid = make("cloud/mid")
    public static let cloudHigh = make("cloud/high")
    // Text and surfaces (system colours)
    public static let textPrimary = make("text/primary")
    public static let textSecondary = make("text/secondary")
    public static let textTertiary = make("text/tertiary")
    public static let textDisabled = make("text/quaternary")
    public static let separator = make("separator/default")
    public static let backgroundWindow = make("background/window")
    public static let backgroundControl = make("background/control")
    public static let backgroundContent = make("background/content")

    /// Fill for a Light Index band. Single hue, ordered by lightness; always print the band word beside it.
    public static func ramp(_ band: LightBand) -> Color { rampColors[band.rawValue] }

    /// Text or icon colour on `ramp(band)` (4.5:1 or better).
    public static func rampText(_ band: LightBand) -> Color { rampTextColors[band.rawValue] }

    /// Registry name of the ramp fill / text token for a band.
    public static func rampTokenName(_ band: LightBand) -> String { "light/ramp/\(bandKey(band))" }
    public static func rampTextTokenName(_ band: LightBand) -> String { "light/rampText/\(bandKey(band))" }

    static func bandKey(_ band: LightBand) -> String {
        switch band {
        case .poor: "poor"
        case .fair: "fair"
        case .good: "good"
        case .great: "great"
        case .epic: "epic"
        }
    }

    private static let rampColors: [Color] = LightBand.allCases.map { make(rampTokenName($0)) }
    private static let rampTextColors: [Color] = LightBand.allCases.map { make(rampTextTokenName($0)) }

    /// The SwiftUI colour for any registry token.
    public static func make(_ name: String) -> Color { color(for: TokenValues.color(name)) }

    public static func color(for token: ColorToken) -> Color {
        #if canImport(AppKit)
        if let alias = token.systemAlias, let system = systemColor(alias) { return Color(nsColor: system) }
        let (l, d) = (token.lightRGB, token.darkRGB)
        return Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let c = isDark ? d : l
            return NSColor(srgbRed: CGFloat(c.red) / 255, green: CGFloat(c.green) / 255, blue: CGFloat(c.blue) / 255, alpha: 1)
        })
        #elseif canImport(UIKit)
        if let alias = token.systemAlias, let system = systemColor(alias) { return Color(uiColor: system) }
        let (l, d) = (token.lightRGB, token.darkRGB)
        return Color(uiColor: UIColor { traits in
            let c = traits.userInterfaceStyle == .dark ? d : l
            return UIColor(red: CGFloat(c.red) / 255, green: CGFloat(c.green) / 255, blue: CGFloat(c.blue) / 255, alpha: 1)
        })
        #else
        return Color(red: Double(token.lightRGB.red) / 255, green: Double(token.lightRGB.green) / 255, blue: Double(token.lightRGB.blue) / 255)
        #endif
    }

    /// System colour aliases the registry may name. Unknown aliases fall back to the token's hex values.
    public static let supportedSystemAliases: [String] = [
        "labelColor", "secondaryLabelColor", "tertiaryLabelColor", "quaternaryLabelColor",
        "separatorColor", "windowBackgroundColor", "controlBackgroundColor", "textBackgroundColor",
    ]

    #if canImport(AppKit)
    private static func systemColor(_ alias: String) -> NSColor? {
        switch alias {
        case "labelColor": .labelColor
        case "secondaryLabelColor": .secondaryLabelColor
        case "tertiaryLabelColor": .tertiaryLabelColor
        case "quaternaryLabelColor": .quaternaryLabelColor
        case "separatorColor": .separatorColor
        case "windowBackgroundColor": .windowBackgroundColor
        case "controlBackgroundColor": .controlBackgroundColor
        case "textBackgroundColor": .textBackgroundColor
        default: nil
        }
    }
    #elseif canImport(UIKit)
    private static func systemColor(_ alias: String) -> UIColor? {
        switch alias {
        case "labelColor": .label
        case "secondaryLabelColor": .secondaryLabel
        case "tertiaryLabelColor": .tertiaryLabel
        case "quaternaryLabelColor": .quaternaryLabel
        case "separatorColor": .separator
        case "windowBackgroundColor": .systemBackground
        case "controlBackgroundColor": .secondarySystemBackground
        case "textBackgroundColor": .systemBackground
        default: nil
        }
    }
    #endif
}
