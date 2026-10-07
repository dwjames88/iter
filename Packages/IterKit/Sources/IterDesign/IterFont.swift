import SwiftUI

/// Semantic fonts. System fonts only; each maps to a `Font.TextStyle`, so system sizing and Dynamic Type still apply.
public enum IterFont {
    public static let titleSpot = make("type/title/spot")
    public static let titleSection = make("type/title/section")
    public static let headline = make("type/headline")
    public static let body = make("type/body")
    public static let bodyEmphasis = make("type/bodyEmphasis")
    public static let callout = make("type/callout")
    public static let subheadline = make("type/subheadline")
    public static let secondary = make("type/secondary")
    public static let moduleTitle = make("type/moduleTitle")
    public static let footnote = make("type/footnote")
    public static let caption = make("type/caption")
    public static let captionStrong = make("type/captionStrong")
    public static let scoreLarge = make("type/score/large")
    public static let scoreMedium = make("type/score/medium")
    public static let scoreBadge = make("type/score/badge")
    public static let time = make("type/time")
    public static let timeSmall = make("type/timeSmall")

    public static func make(_ name: String) -> Font { font(for: TokenValues.typography(name)) }

    public static func font(for token: TypographyToken) -> Font {
        var font = Font.system(token.style.textStyle, design: token.design.swiftUI, weight: token.weight.swiftUI)
        if token.monospacedDigits { font = font.monospacedDigit() }
        return font
    }
}

extension TextStyleName {
    var textStyle: Font.TextStyle {
        switch self {
        case .largeTitle: .largeTitle
        case .title: .title
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .subheadline: .subheadline
        case .body: .body
        case .callout: .callout
        case .footnote: .footnote
        case .caption: .caption
        case .caption2: .caption2
        }
    }
}

extension FontWeightName {
    var swiftUI: Font.Weight {
        switch self {
        case .ultraLight: .ultraLight
        case .thin: .thin
        case .light: .light
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        case .heavy: .heavy
        case .black: .black
        }
    }
}

extension FontDesignName {
    var swiftUI: Font.Design {
        switch self {
        case .standard: .default
        case .serif: .serif
        case .rounded: .rounded
        case .monospaced: .monospaced
        }
    }
}
