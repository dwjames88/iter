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

    @State private var position: MapCameraPosition = .automatic
    @State private var chosenDay: Int?
    @State private var distance: CLLocationDistance = 400_000

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
            } else {
                liveMap
            }
        }
        .overlay(alignment: .topLeading) { dayPicker.padding(IterSpace.md) }
        .accessibilityLabel(Text("Route map", comment: "Accessibility label"))
        .onAppear(perform: fit)
        .onChange(of: entries.map(\.id)) { fit() }
        .onChange(of: selection) { center(on: selection) }
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
        .onMapCameraChange { context in distance = context.camera.distance }
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

    // MARK: Day picker

    @ViewBuilder private var dayPicker: some View {
        let indices = builder.days.filter { !$0.stops.isEmpty }.map(\.index)
        if indices.count > 1 {
            let picker = Picker(selection: Binding(get: { activeDay }, set: { chosenDay = $0; selection = nil })) {
                ForEach(indices, id: \.self) { index in
                    Text("Day \(index + 1)", comment: "Map day picker segment").tag(index)
                }
            } label: {
                Text("Route day", comment: "Accessibility label of the map day picker")
            }
            .labelsHidden()
            Group {
                if indices.count <= 5 {
                    picker.pickerStyle(.segmented)
                } else {
                    picker.pickerStyle(.menu)
                }
            }
            .fixedSize()
            .padding(IterSpace.xs)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: IterRadius.control, style: .continuous))
        }
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

    private static func coordinate(_ c: Coordinate) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: c.latitude, longitude: c.longitude)
    }

    /// Shows the whole trip.
    private func fit() {
        guard let region = GeoRegion.enclosing(entries.map { $0.stop.spot.coordinate }, padding: 0.4, minimumDelta: 0.1) else { return }
        position = .region(MKCoordinateRegion(center: Self.coordinate(region.center),
                                              span: MKCoordinateSpan(latitudeDelta: region.latitudeDelta, longitudeDelta: region.longitudeDelta)))
    }

    /// Centres the pin of the stop selected in the list, keeping the zoom.
    private func center(on id: UUID?) {
        guard let id, let entry = entries.first(where: { $0.id == id }) else { return }
        withAnimation { position = .camera(MapCamera(centerCoordinate: Self.coordinate(entry.stop.spot.coordinate), distance: distance)) }
    }
}
