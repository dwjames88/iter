import SwiftUI
import MapKit
import IterCore
import IterDesign
import IterFeatures

/// The Locations map: a marker per listed spot, framed to fit them, selection shared with the list.
/// Snapshot renders draw `MapStandIn` instead (a live map does not render offscreen).
struct LocationsMap: View {
    let items: [SavedItem]
    @Binding var selection: Set<UUID>
    @Environment(\.renderMode) private var renderMode
    @State private var position: MapCameraPosition
    @State private var paneSize = CGSize.zero

    init(items: [SavedItem], selection: Binding<Set<UUID>>) {
        self.items = items
        _selection = selection
        // Start framed, so MapKit never shows its automatic world camera first.
        _position = State(initialValue: Self.framing(items))
    }

    var body: some View {
        ZStack {
            if renderMode == .snapshot {
                MapStandIn(pins: items.map {
                    .init(id: $0.id.uuidString, coordinate: $0.spot.coordinate, label: $0.spot.name, selected: selection.contains($0.id))
                })
            } else if paneSize.width > 0, paneSize.height > 0 {
                liveMap
            } else {
                Color.clear
            }
        }
        // MapKit's Map extends itself under the toolbar; keep it inside the safe area so the bar stays one plain strip.
        .clipped()
        .onGeometryChange(for: CGSize.self) { $0.size } action: { paneSize = $0 }
        .onChange(of: items.map(\.id)) { withAnimation { position = Self.framing(items) } }
    }

    private var liveMap: some View {
        Map(position: $position, selection: mapSelection) {
            ForEach(items) { item in
                Marker(item.spot.name, systemImage: LightText.symbol(item.spot.category),
                       coordinate: CLLocationCoordinate2D(latitude: item.spot.coordinate.latitude, longitude: item.spot.coordinate.longitude))
                    .tint(selection.contains(item.id) ? IterColor.mapPin : IterColor.mapPinInactive)
                    .tag(item.id)
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .mapControls {
            MapZoomStepper()
            MapCompass()
            MapScaleView()
        }
    }

    /// One marker selected on the map selects its row; a click on empty map clears the selection.
    private var mapSelection: Binding<UUID?> {
        Binding(get: { selection.count == 1 ? selection.first : nil },
                set: { selection = $0.map { [$0] } ?? [] })
    }

    private static func framing(_ items: [SavedItem]) -> MapCameraPosition {
        guard let r = GeoRegion.enclosing(items.map(\.spot.coordinate), padding: 0.4, minimumDelta: 0.2) else { return .automatic }
        return .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: r.center.latitude, longitude: r.center.longitude),
            span: MKCoordinateSpan(latitudeDelta: r.latitudeDelta, longitudeDelta: r.longitudeDelta)))
    }
}
