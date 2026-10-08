import SwiftUI
import IterDesign

/// The Apple Maps layout: the map fills the window, under the toolbar, and the screen's list floats over the map's
/// leading edge on one Liquid Glass panel. The map gets `insets` (the toolbar above, the panel on the leading edge) for
/// its safe area, so framing, selection and the map's own controls stay in the part of the map that shows.
struct FloatingPanelLayout<Panel: View, MapContent: View>: View {
    var panelWidth: CGFloat = IterSize.listIdeal
    @ViewBuilder var panel: Panel
    @ViewBuilder var map: (_ insets: EdgeInsets) -> MapContent
    @State private var topInset: CGFloat = 0
    @State private var totalWidth: CGFloat = 0

    /// The panel narrows (to the list column minimum) before the visible map drops below the detail minimum.
    private var width: CGFloat {
        guard totalWidth > 0 else { return panelWidth }
        return max(IterSize.listColumnMin, min(panelWidth, totalWidth - 2 * Self.margin - IterSize.detailMin))
    }

    /// Apple Maps' card: 8 pt from the window's edges, corners concentric with the window's.
    static var margin: CGFloat { IterSpace.sm }
    static var cornerRadius: CGFloat { 16 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            map(EdgeInsets(top: topInset, leading: width + 2 * Self.margin, bottom: 0, trailing: 0))
                .ignoresSafeArea(edges: .top)
            panel
                .frame(width: width)
                .frame(maxHeight: .infinity)
                .clipShape(.rect(cornerRadius: Self.cornerRadius))
                .glassEffect(.regular, in: .rect(cornerRadius: Self.cornerRadius))
                .padding(Self.margin)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { topInset = $0 }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { totalWidth = $0 }
        // As in Maps, the map runs under the toolbar with no bar or edge of its own.
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
    }
}
