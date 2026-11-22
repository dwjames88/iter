import SwiftUI

/// The round buttons in a floating card's corners (Share, Close, a card's filter menu): a 32 pt interactive Liquid Glass
/// circle with a primary glyph, as Maps' card buttons are. A custom style because the Mac's system glass style has no
/// size between 23 and 34 pt and a `Menu` ignores it (drawing a flat circle). Figma part: corner button.
public struct GlassCircleButtonStyle: ButtonStyle {
    public nonisolated static var size: CGFloat { GlassGeometry.cornerButton }
    /// From the card's edges, so the card's corner is concentric with the button (16 + 11.5 = 27.5 pt).
    public nonisolated static var inset: CGFloat { GlassGeometry.cornerButtonInset }

    /// The circle's diameter (32 pt by default; the Trip Builder's header asks for 36).
    public var diameter: CGFloat

    public init(diameter: CGFloat = GlassCircleButtonStyle.size) { self.diameter = diameter }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(.iconOnly)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: diameter, height: diameter)
            .contentShape(.circle)
            .glassEffect(.regular.interactive(), in: .circle)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

extension ButtonStyle where Self == GlassCircleButtonStyle {
    /// The corner glass circle (32 pt, or `diameter`).
    public static func glassCircle(diameter: CGFloat = GlassCircleButtonStyle.size) -> GlassCircleButtonStyle {
        GlassCircleButtonStyle(diameter: diameter)
    }
}
