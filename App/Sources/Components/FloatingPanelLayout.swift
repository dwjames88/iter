import SwiftUI
import AppKit
import IterCore
import IterDesign
import IterFeatures

/// The Apple Maps layout: the map fills the window, under the toolbar, and the screen's list floats over the map's
/// leading edge on one Liquid Glass panel. The map gets `insets` (the toolbar above, the panel on the leading edge) for
/// its safe area, so framing, selection and the map's own controls stay in the part of the map that shows.
struct FloatingPanelLayout<Panel: View, MapContent: View>: View {
    /// Where the card sits. `.leading` (Explore, Locations) hugs the sidebar edge at `panelWidth`; `.planner` (the trip
    /// builder) follows the window's width (`PlannerCardLayout`): centred and wide in a big window, centred and narrowed
    /// so the map keeps 40 % of the window in a medium one, docked to the leading edge like `.leading` in a small one.
    enum Placement: Equatable {
        case leading
        case planner
    }

    /// The measured sizes the layout is decided from. Whole numbers in steps of 4 pt for the planner, so a live resize
    /// writes state a quarter as often and the mode is only re-decided when the width has moved.
    private struct Measure: Equatable {
        var window: CGFloat = 0
        var detail: CGFloat = 0
        /// The area's leading edge in the window: 0 when the sidebar is collapsed and the window's controls float over it.
        var leading: CGFloat = 0
    }

    var panelWidth: CGFloat = IterSize.listIdeal
    var placement: Placement = .leading
    @ViewBuilder var panel: Panel
    @ViewBuilder var map: (_ insets: EdgeInsets) -> MapContent
    @State private var topInset: CGFloat = 0
    @State private var measure = Measure()
    /// The planner's mode in use, kept for the hysteresis at the thresholds.
    @State private var plannerMode: PlannerCardLayout.Mode?

    private var totalWidth: CGFloat { measure.detail }

    /// The planner's decision for the width measured now (see `PlannerCardLayout`).
    private var planner: PlannerCardLayout {
        PlannerCardLayout.resolve(windowWidth: measure.window, detailWidth: measure.detail, previous: plannerMode,
                                  sideWidth: panelWidth, floorWidth: IterSize.listColumnMin, detailMin: IterSize.detailMin)
    }

    /// Docked to the leading edge: always for `.leading`, and for the planner in a small window.
    private var isDocked: Bool {
        switch placement {
        case .leading: true
        case .planner: planner.mode == .side
        }
    }

    /// The panel narrows (to the list column minimum) before the visible map drops below the detail minimum.
    private var width: CGFloat {
        guard totalWidth > 0 else { return placement == .leading ? panelWidth : PlannerCardLayout.wideMin }
        switch placement {
        case .leading: return max(IterSize.listColumnMin, min(panelWidth, totalWidth - 2 * Self.margin - IterSize.detailMin))
        case .planner: return planner.cardWidth
        }
    }

    /// The map's safe area: the toolbar above, and the card when it sits on the leading edge. A centred card covers the
    /// middle of the map, which no edge inset can describe; the map frames its content in the strip on the card's leading
    /// side (the card's trailing side and the map controls are left alone), so a fitted route is never behind the card.
    private var mapInsets: EdgeInsets {
        if isDocked { return EdgeInsets(top: topInset, leading: width + 2 * Self.margin, bottom: 0, trailing: 0) }
        return EdgeInsets(top: topInset, leading: 0, bottom: 0, trailing: width + (totalWidth - width) / 2 + Self.margin)
    }

    /// Apple Maps' card: 8 pt from the window's edges, its corners concentric with the window's.
    static var margin: CGFloat { IterSpace.sm }
    /// Concentric with the 32 pt corner buttons 11.5 pt in (16 + 11.5 = 27.5 pt), as Maps' card is with its buttons.
    static var shape: RoundedRectangle { RoundedRectangle(cornerRadius: GlassGeometry.cardCorner, style: .continuous) }

    var body: some View {
        let _ = IterPerf.count("panel.body")
        ZStack(alignment: isDocked ? .topLeading : .top) {
            map(mapInsets)
                .ignoresSafeArea(edges: .top)
            panel
                .environment(\.isOnGlass, true)
                .frame(width: width)
                .frame(maxHeight: .infinity)
                .clipShape(Self.shape)
                .modifier(PanelMaterial(shape: Self.shape))
                .padding(Self.margin)
                // A docked planner card with the sidebar collapsed starts below the toolbar, so the window's controls
                // (traffic lights, sidebar toggle) do not sit on its title.
                .padding(.top, placement == .planner && isDocked && measure.leading == 0 ? topInset : 0)
                // As Maps' card: from the top of the window, in the band beside the sidebar the toolbar leaves free.
                .ignoresSafeArea(edges: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { topInset = $0 }
        .onGeometryChange(for: Measure.self) { [placement, dockedCap = panelWidth + 2 * Self.margin + IterSize.detailMin] proxy in
            // The window's content width is this area's trailing edge in window coordinates (the sidebar, when it shows,
            // is what lies to the leading side).
            // A docked card only reads the width below `dockedCap` (above it nothing changes), so a window that is wide enough
            // writes no state while it resizes.
            guard placement == .planner else { return Measure(window: 0, detail: min(proxy.size.width, dockedCap)) }
            func step(_ value: CGFloat) -> CGFloat { (value / 4).rounded() * 4 }
            let frame = proxy.frame(in: .global)
            return Measure(window: step(frame.maxX), detail: step(proxy.size.width), leading: frame.minX < 1 ? 0 : 1)
        } action: { new in
            measure = new
            if placement == .planner {
                let mode = PlannerCardLayout.mode(windowWidth: new.window, previous: plannerMode)
                if mode != plannerMode { plannerMode = mode }
            }
        }
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
                // The header's top is the window's title bar band, where AppKit would take a click for a window drag.
                .titlebarClickable()
                .fixedSize()
                .padding(GlassCircleButtonStyle.inset)
        }
    }
}
