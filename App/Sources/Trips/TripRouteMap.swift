import SwiftUI
import MapKit
import IterCore
import IterDesign
import IterFeatures

/// The route: numbered pins, the selected day's drive in the route colour, other days dimmed (with no day selected, every
/// day is at full strength). The list is the plan; the map is the sanity check (pattern #9). Selecting a pin selects the
/// stop, and the other way round. A day switcher overlaid at the top matches the overview strip.
struct TripRouteMap: View {
    @Environment(\.renderMode) private var renderMode
    @Environment(AppModel.self) private var app
    @AppStorage(MapStyleChoice.storageKey) private var mapStyleRaw = MapStyleChoice.default.rawValue
    let builder: TripBuilderModel
    @Binding var selection: UUID?
    /// The selected day (0-based), shared with the overview strip and the list; nil: all days.
    @Binding var selectedDay: Int?
    /// What covers the map: the toolbar above it and the panel floating over its leading edge.
    var insets = EdgeInsets()
    @Namespace private var mapScope

    @State private var position: MapCameraPosition
    /// True once the map wrote a user-positioned `position` (pan, zoom, stepper, compass) that has not settled yet.
    @State private var userInteracted = false
    @State private var paneSize = CGSize.zero
    @State private var appliedRequest = 0
    /// The road paths as `CLLocationCoordinate2D`, kept while a drive's path is unchanged so a selection or day change
    /// does not rebuild every polyline's coordinates.
    @State private var paths = PathCache()

    init(builder: TripBuilderModel, selection: Binding<UUID?>, selectedDay: Binding<Int?>, insets: EdgeInsets = EdgeInsets()) {
        self.builder = builder
        self.insets = insets
        _selection = selection
        _selectedDay = selectedDay
        // Start framed, so MapKit never shows (and reports) its automatic world camera.
        if let r = builder.initialCameraRegion {
            _position = State(initialValue: .region(Self.mkRegion(r)))
        } else {
            _position = State(initialValue: .automatic)
        }
    }

    /// Whether a day is drawn at full strength: every day when none is selected, else only the selected one.
    private func isActive(day: Int) -> Bool { selectedDay == nil || selectedDay == day }

    var body: some View {
        let _ = IterPerf.count("trip.mapBody")
        Group {
            if renderMode == .snapshot {
                MapStandIn(pins: builder.mapContent.pins.map { pin in
                    MapStandIn.Pin(id: pin.id.uuidString, coordinate: pin.coordinate, label: "\(pin.number)",
                                   selected: pin.id == selection || isActive(day: pin.day))
                }, route: routeCoordinates())
            } else if paneSize.width > 0, paneSize.height > 0 {
                // Created only once the pane has a real size: a map framed before layout settles on MapKit's own
                // default camera, not our region.
                liveMap
            } else {
                Color.clear
            }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { paneSize = $0 }
        .overlay(alignment: .top) {
            TripDaySwitcher(days: builder.mapContent.days.map { ($0.index, $0.date) }, selectedDay: $selectedDay)
                .padding(IterSpace.md)
                .padding(.top, insets.top)
                .padding(.leading, insets.leading)
        }
        .accessibilityLabel(Text("Route map", comment: "Accessibility label"))
        .onAppear {
            IterPerf.once("trip.map.appear")
            builder.setFocusDay(selectedDay)
            builder.requestInitialCamera()
            if let request = builder.cameraRequest { apply(request, animated: false) }
        }
        .onChange(of: selectedDay) { builder.setFocusDay(selectedDay) }
        .onChange(of: builder.fitCoordinates) { builder.contentChanged() }
        .onChange(of: builder.cameraRequest) { _, request in
            if let request { apply(request, animated: true) }
        }
    }

    // MARK: Map

    private func locate() {
        withAnimation(.smooth) { position = .userLocation(fallback: position) }
    }

    private var liveMap: some View {
        Map(position: $position, selection: $selection, scope: mapScope) {
            let content = builder.mapContent
            ForEach(content.legs) { leg in
                let coordinates = paths.coordinates(for: leg)
                if isActive(day: leg.day) {
                    MapPolyline(coordinates: coordinates).stroke(IterColor.backgroundWindow, lineWidth: IterStroke.routeCasing)
                    MapPolyline(coordinates: coordinates).stroke(IterColor.route, lineWidth: IterStroke.route)
                } else {
                    MapPolyline(coordinates: coordinates).stroke(IterColor.routeInactive, lineWidth: IterStroke.routeInactive)
                }
            }
            UserLocationMapContent(location: app.location)
            ForEach(content.pins) { pin in
                Annotation(pin.name, coordinate: Self.coordinate(pin.coordinate), anchor: .center) {
                    self.pin(pin)
                }
                .tag(pin.id)
            }
        }
        .mapStyle(MapStyleChoice(stored: mapStyleRaw).mapStyle())
        .mapControls { MapScaleView() }
        .safeAreaPadding(insets)
        .overlay(alignment: .topTrailing) {
            MapControlStack(scope: mapScope, locate: app.location.showsSystemIndicator ? { locate() } : nil)
                .padding(.top, insets.top)
        }
        .mapScope(mapScope)
        .onMapCameraChange(frequency: .onEnd) { context in
            IterPerf.once("trip.map.firstSettle")
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

    private func pin(_ pin: TripMapPin) -> some View {
        let selected = pin.id == selection
        let inDay = isActive(day: pin.day)
        let size = selected ? IterSize.mapPinSelected : IterSize.mapPin
        return Text(pin.number, format: .number)
            .font(IterFont.captionStrong)
            .monospacedDigit()
            .foregroundStyle(inDay ? IterColor.onAccent : IterColor.backgroundWindow)
            .frame(width: size, height: size)
            .background(inDay ? IterColor.accentEmphasis : IterColor.mapPinInactive, in: Circle())
            .overlay(Circle().strokeBorder(IterColor.backgroundWindow, lineWidth: selected ? IterStroke.thick : IterStroke.thin))
            .opacity(inDay || selected ? 1 : Self.dimmedOpacity)
            .accessibilityLabel(Text("Stop \(pin.number), \(pin.name)", comment: "VoiceOver: map pin"))
    }

    /// Pins of days that are not selected.
    private static let dimmedOpacity = 0.55

    // MARK: Geometry

    /// The road paths of every day at full strength, for the snapshot stand-in.
    private func routeCoordinates() -> [Coordinate] {
        let content = builder.mapContent
        let legs = Dictionary(content.legs.map { ($0.id, $0.path) }, uniquingKeysWith: { first, _ in first })
        return content.pins.filter { isActive(day: $0.day) }.flatMap { pin in legs[pin.id] ?? [pin.coordinate] }
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
}

// MARK: - Path cache

/// Converts a drive's road path to map coordinates once, and again only when the path itself changes. Plain storage the
/// map's body reads and fills; nothing observes it.
@MainActor
private final class PathCache {
    private var entries: [UUID: (path: [Coordinate], coordinates: [CLLocationCoordinate2D])] = [:]

    func coordinates(for leg: TripMapLeg) -> [CLLocationCoordinate2D] {
        if let entry = entries[leg.id], entry.path == leg.path { return entry.coordinates }
        let coordinates = leg.path.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        entries[leg.id] = (leg.path, coordinates)
        return coordinates
    }
}

// MARK: - Day switcher

/// "‹  Day 2 · Thu, Oct 8  ›" over the map's top edge, matching the overview strip. The arrows step through the days and
/// All Days; the title opens a menu of them.
struct TripDaySwitcher: View {
    let days: [(index: Int, date: LocalDay)]
    @Binding var selectedDay: Int?

    var body: some View {
        if days.count > 1 {
            HStack(spacing: IterSpace.xs) {
                Button { step(-1) } label: { Image(systemName: "chevron.left") }
                    .help(Text("Previous day", comment: "Tooltip"))
                    .accessibilityLabel(Text("Previous day", comment: "Accessibility label"))
                Menu {
                    Button(String(localized: "All Days", comment: "Map day switcher: show every day")) { selectedDay = nil }
                    Divider()
                    ForEach(days, id: \.index) { day in
                        Button(TimeText.daySwitcher(index: day.index, day: day.date)) { selectedDay = day.index }
                    }
                } label: {
                    Text(title).monospacedDigit().frame(minWidth: 150)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(Text("Choose the day shown on the map", comment: "Tooltip"))
                Button { step(1) } label: { Image(systemName: "chevron.right") }
                    .help(Text("Next day", comment: "Tooltip"))
                    .accessibilityLabel(Text("Next day", comment: "Accessibility label"))
            }
            .buttonStyle(.borderless)
            .font(IterFont.subheadline)
            .padding(.horizontal, IterSpace.md)
            .padding(.vertical, IterSpace.xs)
            .glassEffect(.regular, in: .capsule)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("Map day", comment: "Accessibility label of the map's day switcher"))
        }
    }

    private var title: String {
        guard let selectedDay, let day = days.first(where: { $0.index == selectedDay }) else {
            return String(localized: "All Days", comment: "Map day switcher: every day is shown")
        }
        return TimeText.daySwitcher(index: day.index, day: day.date)
    }

    /// Steps through the days with All Days as one more stop in the loop: previous from the first day, and next from the
    /// last day, go to All Days.
    private func step(_ delta: Int) {
        let slots: [Int?] = [nil] + days.map { Optional($0.index) }
        let current = slots.firstIndex { $0 == selectedDay } ?? 0
        selectedDay = slots[(current + delta + slots.count) % slots.count]
    }
}
