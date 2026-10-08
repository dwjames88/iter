import SwiftUI
import MapKit
import IterDesign

/// The map's controls as Apple Maps stacks them on the trailing edge: map style and your location share one glass
/// capsule, then zoom, then the compass. The MapKit controls reach the map through `scope` (`Map(scope:)`).
struct MapControlStack: View {
    let scope: Namespace.ID
    /// Centres the map on the user. Nil when there is no location to show.
    var locate: (() -> Void)?

    /// Apple Maps' control width and the gap between groups.
    static var size: CGFloat { 36 }
    static var gap: CGFloat { 6 }

    var body: some View {
        VStack(spacing: Self.gap) {
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
        .padding(IterSpace.sm)
    }
}
