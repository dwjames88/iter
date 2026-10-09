import SwiftUI
import AppKit
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

    /// Apple Maps' card: 8 pt from the window's edges, its corners concentric with the window's.
    static var margin: CGFloat { IterSpace.sm }
    /// Concentric with the 32 pt corner buttons 11.5 pt in (16 + 11.5 = 27.5 pt), as Maps' card is with its buttons.
    static var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 27.5, style: .continuous) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            map(EdgeInsets(top: topInset, leading: width + 2 * Self.margin, bottom: 0, trailing: 0))
                .ignoresSafeArea(edges: .top)
            panel
                .environment(\.isOnGlass, true)
                .frame(width: width)
                .frame(maxHeight: .infinity)
                .clipShape(Self.shape)
                .modifier(PanelMaterial(shape: Self.shape))
                .padding(Self.margin)
                // As Maps' card: from the top of the window, in the band beside the sidebar the toolbar leaves free.
                .ignoresSafeArea(edges: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { topInset = $0 }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { totalWidth = $0 }
        // As in Maps, the map runs under the toolbar with no bar or edge of its own.
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
    }
}

/// The panel's material: the same Liquid Glass the system draws for a window's sidebar. AppKit's sidebar is an
/// `NSGlassEffectView` in its sidebar variant (read from the live view: `_variant` 17), which frosts the content behind it
/// more than the default variant; Maps' card measures the same as its sidebar. The glass is clipped to the panel's
/// concentric shape, as the system clips the sidebar.
private struct PanelMaterial: ViewModifier {
    let shape: RoundedRectangle

    func body(content: Content) -> some View {
        content.background { SidebarGlass().clipShape(shape) }
    }
}

private struct SidebarGlass: NSViewRepresentable {
    /// `NSGlassEffectView`'s private variant for a window sidebar (macOS 26 and 27).
    private static let sidebarVariant = 17

    func makeNSView(context: Context) -> NSGlassEffectView {
        let view = NSGlassEffectView()
        let setter = NSSelectorFromString("set_variant:")
        if view.responds(to: setter) { view.setValue(Self.sidebarVariant, forKey: "_variant") }
        return view
    }

    func updateNSView(_ nsView: NSGlassEffectView, context: Context) {}
}

/// A floating panel's header, as Maps titles its cards: a bold title with a quiet line under it, and round glass
/// actions trailing. The panel carries the screen's title, so the toolbar shows none over the map.
struct FloatingPanelHeader<Accessory: View>: View {
    let title: String
    var subtitle: Text?
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(spacing: IterSpace.sm) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.title.bold())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    subtitle
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: GlassCircleButtonStyle.size + IterSpace.sm)
        }
        .padding(.horizontal, IterSpace.lg)
        .padding(.top, IterSpace.lg)
        .padding(.bottom, IterSpace.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        // The card's buttons sit in its corner, concentric with it, as on the place card.
        .overlay(alignment: .topTrailing) {
            HStack(spacing: IterSpace.sm) { accessory }
                .buttonStyle(GlassCircleButtonStyle())
                .menuStyle(.button)
                .menuIndicator(.hidden)
                .padding(GlassCircleButtonStyle.inset)
        }
    }
}
