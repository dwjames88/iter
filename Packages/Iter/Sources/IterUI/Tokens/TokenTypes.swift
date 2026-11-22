import Foundation

/// Text styles, named after SwiftUI's `Font.TextStyle` without importing SwiftUI, so the registry stays Foundation-only.
public enum TextStyleName: String, CaseIterable, Sendable {
    case largeTitle, title, title2, title3, headline, subheadline, body, callout, footnote, caption, caption2

    /// Default macOS point size of the style at the standard Dynamic Type setting. Reference value for design tools only;
    /// the app uses the system style, so it scales.
    public var referencePoints: Double {
        switch self {
        case .largeTitle: 26
        case .title: 22
        case .title2: 17
        case .title3: 15
        case .headline: 13
        case .subheadline: 11
        case .body: 13
        case .callout: 12
        case .footnote: 10
        case .caption: 10
        case .caption2: 10
        }
    }
}

public enum FontWeightName: String, CaseIterable, Sendable {
    case ultraLight, thin, light, regular, medium, semibold, bold, heavy, black

    /// CSS / DTCG numeric weight.
    public var number: Int {
        switch self {
        case .ultraLight: 100
        case .thin: 200
        case .light: 300
        case .regular: 400
        case .medium: 500
        case .semibold: 600
        case .bold: 700
        case .heavy: 800
        case .black: 900
        }
    }

    public init?(number: Int) {
        guard let match = Self.allCases.first(where: { $0.number == number }) else { return nil }
        self = match
    }
}

public enum FontDesignName: String, CaseIterable, Sendable {
    case standard, serif, rounded, monospaced

    /// Family name for design tools. The app never loads these by name; it uses the system design.
    public var familyName: String {
        switch self {
        case .standard: "SF Pro"
        case .serif: "New York"
        case .rounded: "SF Pro Rounded"
        case .monospaced: "SF Mono"
        }
    }
}

/// A colour with light and dark values. `systemAlias` names a system colour that wins at runtime
/// (the hex values are then only the resolved reference).
public struct ColorToken: Sendable, Hashable {
    public var name: String
    public var light: String
    public var dark: String
    public var systemAlias: String?
    public var description: String

    public init(_ name: String, light: String, dark: String, system: String? = nil, _ description: String) {
        self.name = name
        self.light = light
        self.dark = dark
        self.systemAlias = system
        self.description = description
    }
}

public struct DimensionToken: Sendable, Hashable {
    public var name: String
    public var points: Double
    public var description: String

    public init(_ name: String, _ points: Double, _ description: String) {
        self.name = name
        self.points = points
        self.description = description
    }
}

public struct TypographyToken: Sendable, Hashable {
    public var name: String
    public var style: TextStyleName
    public var weight: FontWeightName
    public var design: FontDesignName
    public var monospacedDigits: Bool
    public var description: String

    public init(_ name: String, _ style: TextStyleName, _ weight: FontWeightName, _ design: FontDesignName,
                monoDigits: Bool, _ description: String) {
        self.name = name
        self.style = style
        self.weight = weight
        self.design = design
        self.monospacedDigits = monoDigits
        self.description = description
    }
}

/// An sRGB colour parsed from `#RRGGBB`.
public struct RGB: Sendable, Hashable {
    public var red: Int, green: Int, blue: Int

    public init(red: Int, green: Int, blue: Int) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public init?(hex: String) {
        guard hex.count == 7, hex.hasPrefix("#"), let v = Int(hex.dropFirst(), radix: 16) else { return nil }
        self.init(red: (v >> 16) & 0xFF, green: (v >> 8) & 0xFF, blue: v & 0xFF)
    }

    public var hex: String { String(format: "#%02X%02X%02X", red, green, blue) }

    /// WCAG 2.x relative luminance.
    public var relativeLuminance: Double {
        func lin(_ v: Int) -> Double {
            let c = Double(v) / 255
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * lin(red) + 0.7152 * lin(green) + 0.0722 * lin(blue)
    }
}

public extension ColorToken {
    var lightRGB: RGB { RGB(hex: light) ?? RGB(red: 255, green: 0, blue: 255) }
    var darkRGB: RGB { RGB(hex: dark) ?? RGB(red: 255, green: 0, blue: 255) }
}

public extension TokenValues {
    private static let colorIndex = Dictionary(colors.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
    private static let dimensionIndex = Dictionary(dimensions.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
    private static let typographyIndex = Dictionary(typography.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })

    /// Lookups trap on an unknown name: a typo in the API layer is a programmer error and the tests cover every name.
    static func color(_ name: String) -> ColorToken {
        guard let t = colorIndex[name] else { preconditionFailure("Unknown colour token \(name)") }
        return t
    }

    static func dimension(_ name: String) -> Double {
        guard let t = dimensionIndex[name] else { preconditionFailure("Unknown dimension token \(name)") }
        return t.points
    }

    static func typography(_ name: String) -> TypographyToken {
        guard let t = typographyIndex[name] else { preconditionFailure("Unknown typography token \(name)") }
        return t
    }
}
