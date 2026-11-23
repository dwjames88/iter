import SwiftUI
import IterUI
#if canImport(AppKit)
import AppKit
#endif

/// The Apple Maps layout: the map fills the detail area, and the card floats over its leading edge on the system's glass.
/// The map gets `insets` (the card's width plus margins on the leading edge) as its safe area, so framing, selection and the
/// map's own controls stay in the part of the map that shows.
struct FindCardLayout<MapContent: View, Card: View>: View {
    var showsCard: Bool
    var cardWidth: CGFloat = IterSize.listIdeal
    @ViewBuilder var map: (_ insets: EdgeInsets) -> MapContent
    @ViewBuilder var card: Card
    @State private var detailWidth: CGFloat = 0

    /// Apple Maps' card: 8 pt from the window's edges, its corners concentric with the window's.
    static var margin: CGFloat { IterSpace.sm }
    static var shape: RoundedRectangle { RoundedRectangle(cornerRadius: GlassGeometry.cardCorner, style: .continuous) }

    /// The card narrows (to the list column minimum) before the visible map drops below the detail minimum.
    static func width(ideal: CGFloat, detailWidth: CGFloat) -> CGFloat {
        guard detailWidth > 0 else { return ideal }
        return max(IterSize.listColumnMin, min(ideal, detailWidth - 2 * margin - IterSize.detailMin))
    }

    private var width: CGFloat { Self.width(ideal: cardWidth, detailWidth: detailWidth) }
    private var insets: EdgeInsets {
        EdgeInsets(top: 0, leading: showsCard ? width + 2 * Self.margin : 0, bottom: 0, trailing: 0)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            map(insets)
            if showsCard {
                card
                    .environment(\.isOnGlass, true)
                    .frame(width: width)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .clipShape(Self.shape)
                    .background { CardGlass(shape: Self.shape) }
                    .padding(Self.margin)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: CGFloat.self) { [cap = cardWidth + 2 * Self.margin + IterSize.detailMin] proxy in
            min(proxy.size.width, cap)
        } action: { detailWidth = $0 }
    }
}

/// The card's material: the same Liquid Glass the system draws for a window's sidebar (an `NSGlassEffectView` in its sidebar
/// variant on the Mac, so card and sidebar are one material), clipped to the card's concentric shape. Elsewhere, `.glassEffect`.
private struct CardGlass: View {
    let shape: RoundedRectangle

    var body: some View {
        #if os(macOS)
        SidebarGlass().clipShape(shape)
        #else
        Color.clear.glassEffect(.regular, in: shape)
        #endif
    }
}

#if os(macOS)
private struct SidebarGlass: NSViewRepresentable {
    /// `NSGlassEffectView`'s private variant for a window sidebar (macOS 26 and 27), as the old Explore card used.
    private static let sidebarVariant = 17

    func makeNSView(context: Context) -> NSGlassEffectView {
        let view = NSGlassEffectView()
        let setter = NSSelectorFromString("set_variant:")
        if view.responds(to: setter) { view.setValue(Self.sidebarVariant, forKey: "_variant") }
        return view
    }

    func updateNSView(_ nsView: NSGlassEffectView, context: Context) {}
}
#endif
