import SwiftUI
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Colours by role. Every value is read from `TokenValues`; nothing here is a literal.
/// Every colour is a concrete First Light token except `backgroundSystemWindow`, which aliases the system window colour.
/// Text colours are `IterInk` so they fall back to the system hierarchy on a selected system-list row.
public enum IterColor {
    // Interface
    public static let accent = make("accent/primary")
    public static let accentText = make("accent/text")
    public static let accentHover = make("accent/hover")
    public static let accentPressed = make("accent/pressed")
    public static let accentDisabled = make("accent/disabled")
    public static let accentEmphasis = make("accent/emphasis")
    public static let onAccent = make("accent/onAccent")
    public static let selection = make("selection/fill")
    public static let focusRing = make("focus/ring")
    // Journey
    public static let route = make("route/active")
    public static let routeInactive = make("route/inactive")
    public static let mapPin = make("map/pin")
    public static let mapPinInactive = make("map/pinInactive")
    public static let userLocation = make("map/userLocation")
    // Light moment
    public static let brandDot = make("brand/dot")
    public static let sun = make("map/sun")
    public static let moon = make("map/moon")
    public static let blueHour = make("light/blueHour")
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
    // Text (IterInk) and surfaces
    public static let textPrimary = IterInk(token: "text/primary", hierarchical: .primary)
    public static let textSecondary = IterInk(token: "text/secondary", hierarchical: .secondary)
    public static let textTertiary = IterInk(token: "text/tertiary", hierarchical: .tertiary)
    public static let textDisabled = IterInk(token: "text/quaternary", hierarchical: .quaternary)
    public static let separator = make("separator/default")
    public static let backgroundWindow = make("background/window")
    public static let backgroundControl = make("background/control")
    public static let backgroundContent = make("background/content")
    public static let backgroundModule = make("background/module")
    public static let backgroundSystemWindow = make("background/systemWindow")
    // Debug overlays
    public static let debugGrid = make("debug/grid")
    public static let debugLane = make("debug/lane")

    /// Fill for a Light Index score (0 to 100, clamped): a continuous ramp from "no light" (white in light appearance,
    /// the dark surface in dark) to the ramp's deepest orange, linear in sRGB between the `light/ramp/*` stops.
    /// A dynamic colour: it resolves per appearance on macOS and iOS.
    public static func ramp(score: Double) -> Color {
        dynamic(light: IterRamp.fill(score: score, dark: false), dark: IterRamp.fill(score: score, dark: true))
    }

    /// Text, score and symbol colour on `ramp(score:)`: ink below the switch score, the inverse from it.
    public static func rampText(score: Double) -> Color {
        dynamic(light: IterRamp.text(score: score, dark: false), dark: IterRamp.text(score: score, dark: true))
    }

    public static func ramp(score: Int) -> Color { rampColors[IterRamp.clamp(score)] }
    public static func rampText(score: Int) -> Color { rampTextColors[IterRamp.clamp(score)] }

    /// Whether a fill at this score needs a separator hairline to read as a shape against the ground.
    public static func rampNeedsHairline(score: Double) -> Bool { score < IterRamp.hairlineBelowScore }
    public static func rampNeedsHairline(score: Int) -> Bool { rampNeedsHairline(score: Double(score)) }

    private static let rampColors: [Color] = (0...100).map { ramp(score: Double($0)) }
    private static let rampTextColors: [Color] = (0...100).map { rampText(score: Double($0)) }

    /// The SwiftUI colour for any registry token.
    public static func make(_ name: String) -> Color { color(for: TokenValues.color(name)) }

    public static func color(for token: ColorToken) -> Color {
        #if canImport(AppKit)
        if let alias = token.systemAlias, let system = systemColor(alias) { return Color(nsColor: system) }
        #elseif canImport(UIKit)
        if let alias = token.systemAlias, let system = systemColor(alias) { return Color(uiColor: system) }
        #endif
        return dynamic(light: token.lightRGB, dark: token.darkRGB)
    }

    /// A colour that resolves to `light` or `dark` with the appearance (macOS and iOS).
    public static func dynamic(light l: RGB, dark d: RGB) -> Color {
        #if canImport(AppKit)
        return Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let c = isDark ? d : l
            return NSColor(srgbRed: CGFloat(c.red) / 255, green: CGFloat(c.green) / 255, blue: CGFloat(c.blue) / 255, alpha: 1)
        })
        #elseif canImport(UIKit)
        return Color(uiColor: UIColor { traits in
            let c = traits.userInterfaceStyle == .dark ? d : l
            return UIColor(red: CGFloat(c.red) / 255, green: CGFloat(c.green) / 255, blue: CGFloat(c.blue) / 255, alpha: 1)
        })
        #else
        return Color(red: Double(l.red) / 255, green: Double(l.green) / 255, blue: Double(l.blue) / 255)
        #endif
    }

    /// System colour aliases the registry may name. Unknown aliases fall back to the token's hex values.
    public static let supportedSystemAliases: [String] = [
        "labelColor", "secondaryLabelColor", "tertiaryLabelColor", "quaternaryLabelColor",
        "separatorColor", "windowBackgroundColor", "controlBackgroundColor", "textBackgroundColor", "systemBlueColor",
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
        case "systemBlueColor": .systemBlue
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
        case "systemBlueColor": .systemBlue
        default: nil
        }
    }
    #endif
}

/// A text colour that is the concrete First Light ink normally, and the system hierarchical style on a selected
/// system-list row (`backgroundProminence == .increased`, where the system fills the row with the accent).
public struct IterInk: ShapeStyle {
    public let token: String
    let hierarchical: HierarchicalShapeStyle

    init(token: String, hierarchical: HierarchicalShapeStyle) {
        self.token = token
        self.hierarchical = hierarchical
    }

    /// The plain colour, for Canvas, GraphicsContext and APIs that need a `Color`.
    public var color: Color { IterColor.make(token) }

    /// `color` with an opacity, for tints.
    public func opacity(_ opacity: Double) -> Color { color.opacity(opacity) }

    public func resolve(in environment: EnvironmentValues) -> AnyShapeStyle {
        environment.backgroundProminence == .increased ? AnyShapeStyle(hierarchical) : AnyShapeStyle(color)
    }
}
