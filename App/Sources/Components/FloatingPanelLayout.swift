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

    /// Apple Maps' card: 8 pt from the window's edges, corners concentric with the window's.
    static var margin: CGFloat { IterSpace.sm }
    static var cornerRadius: CGFloat { 16 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            map(EdgeInsets(top: topInset, leading: width + 2 * Self.margin, bottom: 0, trailing: 0))
                .ignoresSafeArea(edges: .top)
            panel
                .environment(\.isOnGlass, true)
                .frame(width: width)
                .frame(maxHeight: .infinity)
                .clipShape(.rect(cornerRadius: Self.cornerRadius))
                .modifier(PanelMaterial(radius: Self.cornerRadius))
                .padding(Self.margin)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { topInset = $0 }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { totalWidth = $0 }
        // As in Maps, the map runs under the toolbar with no bar or edge of its own.
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
    }
}

/// The panel's material, matched to Maps' card by measurement: in light appearance Maps frosts the map heavily (as its
/// sidebar does), so the card is the window's sidebar material under the glass; in dark appearance it lifts the map a
/// little and keeps its hue, which plain glass does.
private struct PanelMaterial: ViewModifier {
    let radius: CGFloat
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .background {
                if scheme == .light { SidebarMaterial().clipShape(.rect(cornerRadius: radius)) }
            }
            .glassEffect(.regular, in: .rect(cornerRadius: radius))
    }
}

/// The sidebar material, blended with the window's own content (the map), not the desktop.
private struct SidebarMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .withinWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
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
            Spacer(minLength: 0)
            accessory
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .controlSize(.large)
        .menuIndicator(.hidden)
        .padding(.horizontal, IterSpace.lg)
        .padding(.top, IterSpace.lg)
        .padding(.bottom, IterSpace.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
