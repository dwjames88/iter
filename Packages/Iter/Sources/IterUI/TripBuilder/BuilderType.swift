import SwiftUI

/// The Trip Builder's type scale, in the design's points (SF Pro; Regular 400, Semibold 590, Light 274, Heavy 860). One
/// place, so no view picks a size of its own. Fixed sizes like the score chip: the panel is a dense planning surface.
/// Figma part: Trip Builder Module text styles.
public enum BuilderType {
    /// Trip title, 26 Heavy.
    public static let title = Font.system(size: 26, weight: .heavy)
    /// "Tuesday" on a selector card, "Day 1" on a day card, 17 Semibold.
    public static let heading = Font.system(size: 17, weight: .semibold)
    /// Body text, 13 Regular.
    public static let body = Font.system(size: 13, weight: .regular)
    /// Stop names, transfer headline, 13 Semibold.
    public static let bodyStrong = Font.system(size: 13, weight: .semibold)
    /// Small labels, 10 Regular.
    public static let caption = Font.system(size: 10, weight: .regular)
    /// "Set up", "Leave by", counts, 10 Semibold.
    public static let captionStrong = Font.system(size: 10, weight: .semibold)
    /// "Day 1" on a selector card, the session, 10 Light.
    public static let captionLight = Font.system(size: 10, weight: .light)
    /// Buttons, notes and the overnight line, 11 Semibold.
    public static let control = Font.system(size: 11, weight: .semibold)
}

/// Spacing the cards share (points, from the design).
public enum BuilderMetrics {
    /// Panel edge to a card.
    public static let panelInset: CGFloat = 16
    /// The horizontal margin a plain macOS List adds to every row's content, on top of the row insets.
    public static let listMargin: CGFloat = 8
    /// Between the header card, the selector and the day cards.
    public static let sectionGap: CGFloat = 24
    /// A day card's body padding.
    public static let bodyInset: CGFloat = 4
    /// Corner of a day card or the header card (`GlassGeometry.cardCorner`).
    public static let cardCorner: CGFloat = GlassGeometry.cardCorner
    /// Corner of a stop card, a selector card and a transfer card.
    public static let innerCorner: CGFloat = 22
}

extension View {
    /// The soft drop shadow under the header card and the day selector (ink at 12 %, y 6, blur 10). None in dark mode,
    /// where a shadow on a near-black ground only muddies the card.
    public func builderCardShadow() -> some View { modifier(BuilderCardShadow()) }
}

private struct BuilderCardShadow: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content.shadow(color: scheme == .dark ? .clear : IterColor.textPrimary.color.opacity(0.12), radius: 5, x: 0, y: 6)
    }
}

/// A card's solid fill with the design's shadow under it (the shadow belongs to the fill, not to the text on it).
/// Figma part: Trip Builder card fill.
public struct BuilderCardBackground: View {
    public var fill: Color
    public var corner: CGFloat
    public var shadow: Bool

    public init(fill: Color = IterColor.backgroundContent, corner: CGFloat = BuilderMetrics.cardCorner, shadow: Bool = true) {
        self.fill = fill
        self.corner = corner
        self.shadow = shadow
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        if shadow {
            shape.fill(fill).builderCardShadow()
        } else {
            shape.fill(fill)
        }
    }
}
