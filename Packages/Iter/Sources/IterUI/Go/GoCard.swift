import SwiftUI

/// The solid content card behind every trip-mode card: `background/content`, the floating cards' corner
/// (`GlassGeometry.cardCorner`), a hairline in `separator/default`. No glass: cards are content.
struct GoCardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(IterSpace.md + IterSpace.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(IterColor.backgroundContent, in: RoundedRectangle(cornerRadius: GlassGeometry.cardCorner, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: GlassGeometry.cardCorner, style: .continuous)
                    .strokeBorder(IterColor.separator, lineWidth: IterStroke.hairline)
            }
    }
}

extension View {
    func goCard() -> some View { modifier(GoCardBackground()) }
}

/// An icon in a fixed-width lane beside a line of text, so stacked lines align.
struct GoLine<Content: View>: View {
    let symbol: String
    let content: Content
    init(_ symbol: String, @ViewBuilder content: () -> Content) {
        self.symbol = symbol
        self.content = content()
    }
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: IterSpace.sm) {
            Image(systemName: symbol).frame(width: IterSize.iconLarge, alignment: .center).accessibilityHidden(true)
            content
        }
    }
}
