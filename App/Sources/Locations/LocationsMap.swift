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
    /// What covers the map: the toolbar above it and the panel floating over its leading edge.
    var insets = EdgeInsets()
    @Namespace private var mapScope
    @Environment(\.renderMode) private var renderMode
    @Environment(AppModel.self) private var model
    @State private var position: MapCameraPosition
    @State private var paneSize = CGSize.zero
    /// The camera as last settled, so a selection knows whether the map is already closer in than the selection radius.
    @State private var visible: GeoRegion?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(MapStyleChoice.storageKey) private var mapStyleRaw = MapStyleChoice.default.rawValue
    @State private var daylight = DaylightClock()
    @AppStorage(DaylightClock.storageKey) private var showsDaylight = true

    init(items: [SavedItem], selection: Binding<Set<UUID>>, insets: EdgeInsets = EdgeInsets()) {
        self.items = items
        _selection = selection
        self.insets = insets
        // Start framed, so MapKit never shows its automatic world camera first.
        _position = State(initialValue: Self.framing(items))
    }

    var body: some View {
        ZStack {
            if renderMode == .snapshot {
                MapStandIn(pins: drawOrder.map { item in
                    let event = model.savedEvent(for: item.spot)
                    return .init(id: item.id.uuidString, coordinate: item.spot.coordinate, label: item.spot.name,
                                 selected: selection.contains(item.id),
                                 event: event.map { .init(window: $0.window, zone: item.spot.timeZone, isLoading: $0.isLoading, isTomorrow: $0.isTomorrow) })
                })
            } else if paneSize.width > 0, paneSize.height > 0 {
                liveMap
            } else {
                Color.clear
            }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { paneSize = $0 }
        .onChange(of: items.map(\.id)) { withAnimation { position = Self.framing(items) } }
    }

    private var liveMap: some View {
        Map(position: $position, bounds: .globe, selection: mapSelection, scope: mapScope) {
            if daylight.isShown(isOn: showsDaylight, style: MapStyleChoice(stored: mapStyleRaw)) { DaylightOverlay(daylight.shading) }
            ForEach(drawOrder) { item in
                let selected = selection.contains(item.id)
                Annotation(item.spot.name,
                           coordinate: CLLocationCoordinate2D(latitude: item.spot.coordinate.latitude, longitude: item.spot.coordinate.longitude),
                           anchor: selected ? .bottom : .center) {
                    LocationsPinView(spot: item.spot, event: model.savedEvent(for: item.spot), isSelected: selected)
                }
                .tag(item.id)
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(MapStyleChoice(stored: mapStyleRaw).mapStyle())
        .daylightClock(daylight)
        .mapControls { MapScaleView() }
        .safeAreaPadding(insets)
        .overlay(alignment: .topTrailing) {
            MapControlStack(scope: mapScope).padding(.top, insets.top)
        }
        .mapScope(mapScope)
        .onMapCameraChange(frequency: .onEnd) { context in
            let r = context.region
            visible = GeoRegion(center: Coordinate(latitude: r.center.latitude, longitude: r.center.longitude),
                                latitudeDelta: r.span.latitudeDelta, longitudeDelta: r.span.longitudeDelta)
        }
        // Selecting one spot (a row or a pin) frames the selection radius around it, or only pans when already closer.
        .onChange(of: selection) { _, new in
            guard new.count == 1, let item = items.first(where: { $0.id == new.first }) else { return }
            let target = MapCameraPolicy.selectionRegion(current: visible, spot: item.spot.coordinate)
            let region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: target.center.latitude, longitude: target.center.longitude),
                span: MKCoordinateSpan(latitudeDelta: min(target.latitudeDelta, 120), longitudeDelta: min(target.longitudeDelta, 300)))
            if reduceMotion { position = .region(region) } else { withAnimation(.smooth) { position = .region(region) } }
        }
    }

    /// The selected pins last, so they draw on top.
    private var drawOrder: [SavedItem] {
        items.filter { !selection.contains($0.id) } + items.filter { selection.contains($0.id) }
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

/// One Locations map pin: the event unit exactly as Explore draws it (`EventScore` pin variant, borderless, selection
/// by scale and shadow), showing the spot's next sunrise or sunset, the same window as its list row.
private struct LocationsPinView: View {
    let spot: Spot
    let event: SavedEvent?
    let isSelected: Bool


    var body: some View {
        Group {
            if let event {
                EventScore(window: event.window, zone: spot.timeZone, timeStyle: .start, variant: .pin,
                           isLoading: event.isLoading, isTomorrow: event.isTomorrow, isSelected: isSelected)
            } else if isSelected {
                Text(spot.name)
                    .font(IterFont.captionStrong)
                    .foregroundStyle(IterColor.textPrimary)
                    .lineLimit(1)
                    .padding(.vertical, IterSpace.xs)
                    .padding(.horizontal, IterSpace.sm)
                    .background(IterColor.backgroundContent, in: Capsule())
                    .shadow(radius: IterEvent.pinShadowRadiusSelected, y: 1)
                    .scaleEffect(IterEvent.pinScaleSelected, anchor: .bottom)
            } else {
                Circle().fill(IterColor.backgroundControl)
                    .frame(width: IterSpace.sm + IterSpace.xs, height: IterSpace.sm + IterSpace.xs)
                    .overlay(Circle().strokeBorder(IterColor.separator, lineWidth: IterStroke.hairline))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(spot.name))
        .accessibilityValue(event.map { Text(LightText.accessibilityDescription($0.window)) } ?? Text(verbatim: ""))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

}
