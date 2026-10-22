import SwiftUI
import IterDesign

/// The Trip Builder's type scale, in the design's points (SF Pro; Regular 400, Semibold 590, Light 274, Heavy 860). One
/// place, so no view picks a size of its own. Fixed sizes like the score chip: the panel is a dense planning surface.
enum BuilderType {
    /// Trip title, 26 Heavy.
    static let title = Font.system(size: 26, weight: .heavy)
    /// "Tuesday" on a selector card, "Day 1" on a day card, 17 Semibold.
    static let heading = Font.system(size: 17, weight: .semibold)
    /// Body text, 13 Regular.
    static let body = Font.system(size: 13, weight: .regular)
    /// Stop names, transfer headline, 13 Semibold.
    static let bodyStrong = Font.system(size: 13, weight: .semibold)
    /// Small labels, 10 Regular.
    static let caption = Font.system(size: 10, weight: .regular)
    /// "Set up", "Leave by", counts, 10 Semibold.
    static let captionStrong = Font.system(size: 10, weight: .semibold)
    /// "Day 1" on a selector card, the session, 10 Light.
    static let captionLight = Font.system(size: 10, weight: .light)
    /// Buttons, notes and the overnight line, 11 Semibold.
    static let control = Font.system(size: 11, weight: .semibold)
}

/// Spacing the cards share (points, from the design).
enum BuilderMetrics {
    /// Panel edge to a card.
    static let panelInset: CGFloat = 16
    /// The horizontal margin a plain macOS List adds to every row's content, on top of the row insets.
    static let listMargin: CGFloat = 8
    /// Between the header card, the selector and the day cards.
    static let sectionGap: CGFloat = 24
    /// A day card's body padding.
    static let bodyInset: CGFloat = 4
    /// Corner of a day card or the header card (`GlassGeometry.cardCorner`).
    static let cardCorner: CGFloat = GlassGeometry.cardCorner
    /// Corner of a stop card, a selector card and a transfer card.
    static let innerCorner: CGFloat = 22
}

extension View {
    /// The soft drop shadow under the header card and the day selector (#1E0F0A at 12 %, y 6, blur 10). None in dark mode,
    /// where a shadow on a near-black ground only muddies the card.
    func builderCardShadow() -> some View { modifier(BuilderCardShadow()) }
}

private struct BuilderCardShadow: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content.shadow(color: scheme == .dark ? .clear : IterColor.textPrimary.color.opacity(0.12), radius: 5, x: 0, y: 6)
    }
}

/// A card's solid fill with the design's shadow under it (the shadow belongs to the fill, not to the text on it).
struct BuilderCardBackground: View {
    var fill: Color = IterColor.backgroundContent
    var corner: CGFloat = BuilderMetrics.cardCorner
    var shadow = true

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        if shadow {
            shape.fill(fill).builderCardShadow()
        } else {
            shape.fill(fill)
        }
    }
}
