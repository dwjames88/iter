import CoreGraphics

/// The floating cards' glass geometry, measured from Apple Maps (Design/GLASS-RULES.md).
public enum GlassGeometry {
    /// A floating card's corner radius.
    public static let cardCorner: CGFloat = 27.5
    /// The round glass buttons in a card's corners.
    public static let cornerButton: CGFloat = 32
    /// From the card's top and side edges to a corner button, so the card's corner is concentric with the button:
    /// the card's radius minus the button's (27.5 - 16 = 11.5 pt).
    public static let cornerButtonInset: CGFloat = cardCorner - cornerButton / 2
}
