import SwiftUI
import MapKit
import IterCore
import IterDesign
import IterFeatures

/// The route: numbered pins, the selected day's drive in the route colour, other days quieter. The list is the plan;
/// the map is the sanity check (pattern #9). Selecting a pin selects the stop, and the other way round.
struct TripRouteMap: View {
    @Environment(\.renderMode) private var renderMode
    let builder: TripBuilderModel
    @Binding var selection: UUID?
    /// The day picked in the builder's toolbar picker.
    @Binding var chosenDay: Int?

    @State private var position: MapCameraPosition
    /// True once the map wrote a user-positioned `position` (pan, zoom, stepper, compass) that has not settled yet.
    @State private var userInteracted = false
    @State private var paneSize = CGSize.zero
    @State private var appliedRequest = 0

    init(builder: TripBuilderModel, selection: Binding<UUID?>, chosenDay: Binding<Int?>) {
        self.builder = builder
        _selection = selection
        _chosenDay = chosenDay
        // Start framed, so MapKit never shows (and reports) its automatic world camera.
        if let r = builder.initialCameraRegion {
            _position = State(initialValue: .region(Self.mkRegion(r)))
        } else {
            _position = State(initialValue: .automatic)
        }
    }

    private var entries: [TripStopEntry] { builder.days.flatMap(\.stops) }

    /// The day whose route is highlighted: the selected stop's, else the one picked, else the first with stops.
    private var activeDay: Int {
        if let selection, let entry = entries.first(where: { $0.id == selection }) { return entry.stop.dayIndex }
        return chosenDay ?? builder.days.first { !$0.stops.isEmpty }?.index ?? 0
    }

    var body: some View {
        Group {
            if renderMode == .snapshot {
                MapStandIn(pins: entries.map { entry in
                    MapStandIn.Pin(id: entry.id.uuidString, coordinate: entry.stop.spot.coordinate, label: "\(entry.number)",
                                   selected: entry.id == selection || entry.stop.dayIndex == activeDay)
                }, route: routeCoordinates(day: activeDay))
            } else if paneSize.width > 0, paneSize.height > 0 {
                // Created only once the pane has a real size: a map framed before layout settles on MapKit's own
                // default camera, not our region.
                liveMap
            } else {
                Color.clear
            }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { paneSize = $0 }
        // MapKit's Map extends itself under the toolbar; clip it to the safe area so the bar is one plain strip.
        .clipped()
        .accessibilityLabel(Text("Route map", comment: "Accessibility label"))
        .onAppear {
            builder.setFocusDay(chosenDay)
            builder.requestInitialCamera()
            if let request = builder.cameraRequest { apply(request, animated: false) }
        }
        .onChange(of: chosenDay) { builder.setFocusDay(chosenDay) }
        .onChange(of: builder.fitCoordinates) { builder.contentChanged() }
        .onChange(of: builder.cameraRequest) { _, request in
            if let request { apply(request, animated: true) }
        }
        .onChange(of: selection) { reveal(selection) }
    }

    // MARK: Map

    private var liveMap: some View {
        Map(position: $position, selection: $selection) {
            ForEach(builder.days) { day in
                ForEach(legs(into: day.index), id: \.0) { _, coordinates in
                    if day.index == activeDay {
                        MapPolyline(coordinates: coordinates).stroke(IterColor.backgroundWindow, lineWidth: IterStroke.routeCasing)
                        MapPolyline(coordinates: coordinates).stroke(IterColor.route, lineWidth: IterStroke.route)
                    } else {
                        MapPolyline(coordinates: coordinates).stroke(IterColor.routeInactive, lineWidth: IterStroke.routeInactive)
                    }
                }
            }
            ForEach(entries) { entry in
                Annotation(entry.stop.spot.name, coordinate: Self.coordinate(entry.stop.spot.coordinate), anchor: .center) {
                    pin(entry)
                }
                .tag(entry.id)
            }
        }
        .mapControls {
            MapZoomStepper()
            MapCompass()
            MapScaleView()
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            let r = context.region
            // A settle is the user's only when the map wrote a user-positioned `position` (see below); layout and
            // aspect settles MapKit makes on its own never are.
            let byUser = userInteracted
            userInteracted = false
            builder.cameraDidChange(to: GeoRegion(center: Coordinate(latitude: r.center.latitude, longitude: r.center.longitude),
                                                  latitudeDelta: r.span.latitudeDelta, longitudeDelta: r.span.longitudeDelta),
                                    byUser: byUser)
        }
        .onChange(of: position) { _, new in
            if new.positionedByUser { userInteracted = true }
        }
    }

    private func pin(_ entry: TripStopEntry) -> some View {
        let selected = entry.id == selection
        let inDay = entry.stop.dayIndex == activeDay
        let size = selected ? IterSize.mapPinSelected : IterSize.mapPin
        return Text(entry.number, format: .number)
            .font(IterFont.captionStrong)
            .monospacedDigit()
            .foregroundStyle(inDay ? IterColor.onAccent : IterColor.backgroundWindow)
            .frame(width: size, height: size)
            .background(inDay ? IterColor.accentEmphasis : IterColor.mapPinInactive, in: Circle())
            .overlay(Circle().strokeBorder(IterColor.backgroundWindow, lineWidth: selected ? IterStroke.thick : IterStroke.thin))
            .accessibilityLabel(Text("Stop \(entry.number), \(entry.stop.spot.name)", comment: "VoiceOver: map pin"))
    }

    // MARK: Geometry

    /// The drives that end on `day`, each as the road path (or a straight line when the path is unknown).
    private func legs(into day: Int) -> [(UUID, [CLLocationCoordinate2D])] {
        builder.days.first { $0.index == day }?.stops.compactMap { entry in
            guard let leg = entry.schedule?.legFromPrevious else { return nil }
            let path = leg.path.count >= 2 ? leg.path : [leg.from, leg.to]
            return (entry.id, path.map(Self.coordinate))
        } ?? []
    }

    private func routeCoordinates(day: Int) -> [Coordinate] {
        builder.days.first { $0.index == day }?.stops.flatMap { entry -> [Coordinate] in
            guard let leg = entry.schedule?.legFromPrevious else { return [entry.stop.spot.coordinate] }
            return (leg.path.count >= 2 ? leg.path : [leg.from, leg.to])
        } ?? []
    }

    private static func mkRegion(_ target: GeoRegion) -> MKCoordinateRegion {
        MKCoordinateRegion(center: coordinate(target.center),
                           span: MKCoordinateSpan(latitudeDelta: min(target.latitudeDelta, 120),
                                                  longitudeDelta: min(target.longitudeDelta, 300)))
    }

    private static func distinct(_ region: MKCoordinateRegion, from position: MapCameraPosition) -> MKCoordinateRegion {
        guard let current = position.region,
              abs(current.center.latitude - region.center.latitude) < 1e-9,
              abs(current.span.latitudeDelta - region.span.latitudeDelta) < 1e-9 else { return region }
        return MKCoordinateRegion(center: region.center,
                                  span: MKCoordinateSpan(latitudeDelta: region.span.latitudeDelta * 1.00001,
                                                         longitudeDelta: region.span.longitudeDelta))
    }

    private static func coordinate(_ c: Coordinate) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: c.latitude, longitude: c.longitude)
    }

    /// Applies the model's camera command. The model keeps automatic fits within `MapCameraPolicy.maxAutomaticSpan`.
    private func apply(_ request: CameraRequest, animated: Bool) {
        guard request.id != appliedRequest else { return }
        appliedRequest = request.id
        let target: GeoRegion
        switch request.kind {
        case .fit(let r), .pan(let r): target = r
        }
        // Assigning the region the binding already holds does nothing, so a re-application of it is nudged.
        let region = Self.distinct(Self.mkRegion(target), from: position)
        if animated {
            withAnimation(.smooth) { position = .region(region) }
        } else {
            position = .region(region)
        }
    }

    /// Pans to the pin of the stop selected in the list without zooming.
    private func reveal(_ id: UUID?) {
        guard let id, let entry = entries.first(where: { $0.id == id }) else { return }
        builder.reveal(entry.stop.spot.coordinate)
    }
}
