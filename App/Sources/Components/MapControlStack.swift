import SwiftUI
import MapKit
import IterDesign

/// The map's controls as Apple Maps stacks them on the trailing edge: the screen's own map actions in a glass capsule
/// (Explore: Windy and Add Spot), map style and your location in another, then zoom, then the compass. The MapKit
/// controls reach the map through `scope` (`Map(scope:)`).
struct MapControlStack<Actions: View>: View {
    let scope: Namespace.ID
    /// Centres the map on the user. Nil when there is no location to show.
    var locate: (() -> Void)?
    /// The screen's map actions, one 36 pt button each, stacked in their own capsule above the map controls.
    @ViewBuilder var actions: Actions

    /// Apple Maps' control width and the gap between groups.
    static var size: CGFloat { 36 }
    static var gap: CGFloat { 6 }

    var body: some View {
        GlassEffectContainer(spacing: Self.gap) {
        VStack(spacing: Self.gap) {
            if Actions.self != EmptyView.self {
                VStack(spacing: 0) { actions }
                    .buttonStyle(.plain)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)
                    .glassEffect(.regular.interactive(), in: .capsule)
            }
            VStack(spacing: 0) {
                MapStyleMenu()
                if let locate {
                    Button(action: locate) {
                        Image(systemName: "location")
                            .frame(width: Self.size, height: Self.size)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .help(String(localized: "Show your location", comment: "Tooltip"))
                    .accessibilityLabel(Text("Show your location", comment: "Map control"))
                }
            }
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(.primary)
            .glassEffect(.regular.interactive(), in: .capsule)
            MapZoomStepper(scope: scope)
            MapCompass(scope: scope)
                .mapControlVisibility(.visible)
        }
        }
        .padding(IterSpace.sm)
    }
}

extension MapControlStack where Actions == EmptyView {
    init(scope: Namespace.ID, locate: (() -> Void)? = nil) {
        self.init(scope: scope, locate: locate) { EmptyView() }
    }
}

/// One button in a map control capsule: a 36 pt icon, with a tooltip and an accessibility label.
struct MapControlButton: View {
    let title: String
    let systemImage: String
    var help: String?
    var isOn = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .foregroundStyle(isOn ? AnyShapeStyle(IterColor.accent) : AnyShapeStyle(.primary))
                .frame(width: MapControlStack<EmptyView>.size, height: MapControlStack<EmptyView>.size)
                .contentShape(.rect)
        }
        .help(help ?? title)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
