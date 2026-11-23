import SwiftUI
import IterFeatures

// CONTRACT STUB (Phase 6 lead). The Build screens worker replaces the bodies; the type names and inits stay.

/// The Trip Builder panel (header card, day selector, day cards, transfers, source lines). No background of its own: on
/// the Mac it sits in the system inspector, on iPhone in a pushed screen.
public struct TripBuilderPanel: View {
    let model: BuildModel
    public init(model: BuildModel) { self.model = model }
    public var body: some View { Text("Trip Builder") }
}

/// The route map with numbered waypoints for a trip.
public struct TripRouteMap: View {
    let model: BuildModel
    public init(model: BuildModel) { self.model = model }
    public var body: some View { Text("Route map").frame(maxWidth: .infinity, maxHeight: .infinity) }
}
