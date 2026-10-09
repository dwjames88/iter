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
    @State private var daylight = DaylightClock()
    @AppStorage(DaylightClock.storageKey) private var showsDaylight = true
    let builder: TripBuilderModel
    /// The selected stop and day, shared with the day strip and the list.
    let state: TripViewState
    /// What covers the map: the toolbar above it (and the panel, when it floats over the leading edge).
    var insets = EdgeInsets()
    /// The map's own day choice (none today: the card's day strip is the switcher).
    var chooseDay: (Int?) -> Void = { _ in }
    @Namespace private var mapScope

    @State private var position: MapCameraPosition
    /// True once the map wrote a user-positioned `position` (pan, zoom, stepper, compass) that has not settled yet.
    @State private var userInteracted = false
    @State private var paneSize = CGSize.zero
    @State private var appliedRequest = 0
    /// The framing last applied and how often a settle far from it has been corrected.
    @State private var framed: GeoRegion?
    @State private var corrections = 0
    /// The road paths as `CLLocationCoordinate2D`, kept while a drive's path is unchanged so a selection or day change
    /// does not rebuild every polyline's coordinates.
    @State private var paths = PathCache()

    init(builder: TripBuilderModel, state: TripViewState, insets: EdgeInsets = EdgeInsets(), chooseDay: @escaping (Int?) -> Void = { _ in }) {
        self.builder = builder
        self.state = state
        self.insets = insets
        self.chooseDay = chooseDay
        // Start framed, so MapKit never shows (and reports) its automatic world camera.
        if let r = builder.initialCameraRegion {
            _position = State(initialValue: .region(Self.mkRegion(r)))
        } else {
            _position = State(initialValue: .automatic)
        }
    }

    /// Whether a day is drawn at full strength: every day when none is selected, else only the selected one.
    private func isActive(day: Int) -> Bool { state.selectedDay == nil || state.selectedDay == day }

    var body: some View {
        let _ = IterPerf.count("trip.mapBody")
        Group {
            if renderMode == .snapshot {
                MapStandIn(pins: builder.mapContent.pins.map { pin in
                    MapStandIn.Pin(id: pin.id.uuidString, coordinate: pin.coordinate, label: "\(pin.number)",
                                   selected: pin.id == state.selection || isActive(day: pin.day))
                }, route: routeCoordinates())
            } else if paneSize.width > 0, paneSize.height > 0 {
                // Created only once the pane has a real size: a map framed before layout settles on MapKit's own
                // default camera, not our region.
                liveMap
            } else {
                Color.clear
            }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
            let first = paneSize == .zero
            paneSize = size
            // The globe's camera drifts when the pane is laid out again (the card settling), so the framing the model last
            // asked for is applied once more as the map gets its real size.
            if !first, !userInteracted, let request = builder.cameraRequest { apply(request, animated: false, force: true) }
        }
        .accessibilityLabel(Text("Route map", comment: "Accessibility label"))
        .onAppear {
            IterPerf.once("trip.map.appear")
            builder.setFocusDay(state.selectedDay)
            builder.requestInitialCamera()
            if let request = builder.cameraRequest { apply(request, animated: false) }
        }
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
        Map(position: $position, bounds: .globe, selection: Binding(get: { state.selection }, set: { state.select($0, from: .map) }), scope: mapScope) {
            if daylight.isShown(isOn: showsDaylight, style: MapStyleChoice(stored: mapStyleRaw)) { DaylightOverlay(daylight.shading) }
            let content = builder.mapContent
            let selection = state.selection
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
                    TripPinView(number: pin.number, name: pin.name, selected: pin.id == selection, inDay: isActive(day: pin.day))
                        .equatable()
                }
                .tag(pin.id)
            }
        }
        .mapStyle(MapStyleChoice(stored: mapStyleRaw).mapStyle())
        .daylightClock(daylight)
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
            // The globe bounds let MapKit settle on a world camera when it lays out before the card does. A pane's shape
            // never moves the camera that far from what was asked (about 3x at most), so that settle is put right.
            if !byUser, corrections < Self.maxCorrections, let framed,
               max(r.span.latitudeDelta, r.span.longitudeDelta) > Self.worldFactor * max(framed.latitudeDelta, framed.longitudeDelta) {
                corrections += 1
                IterPerf.count("trip.camera.worldCorrected")
                // Assigning the region the binding already holds does nothing, so it is nudged.
                position = .region(Self.distinct(fitted(Self.mkRegion(framed)), from: position))
                return
            }
            builder.cameraDidChange(to: GeoRegion(center: Coordinate(latitude: r.center.latitude, longitude: r.center.longitude),
                                                  latitudeDelta: r.span.latitudeDelta, longitudeDelta: r.span.longitudeDelta),
                                    byUser: byUser)
        }
        .onChange(of: position) { _, new in
            if new.positionedByUser { userInteracted = true }
        }
    }

    // MARK: Geometry

    /// The region to hand the map so the whole of `region` shows in the part of the map the card leaves free. The globe's
    /// camera is sized by the region's height alone, so a route wider than the free strip's shape would be cropped at its
    /// sides: the height is raised until the width fits too.
    private func fitted(_ region: MKCoordinateRegion) -> MKCoordinateRegion {
        let width = paneSize.width - insets.leading - insets.trailing
        let height = paneSize.height - insets.top - insets.bottom
        guard width > 0, height > 0 else { return region }
        let cosine = max(cos(region.center.latitude * .pi / 180), 0.05)
        let needed = region.span.longitudeDelta * cosine * height / width
        guard needed > region.span.latitudeDelta else { return region }
        return MKCoordinateRegion(center: region.center,
                                  span: MKCoordinateSpan(latitudeDelta: min(needed, 120), longitudeDelta: region.span.longitudeDelta))
    }

    /// The road paths of every day at full strength, for the snapshot stand-in.
    private func routeCoordinates() -> [Coordinate] {
        let content = builder.mapContent
        let legs = Dictionary(content.legs.map { ($0.id, $0.path) }, uniquingKeysWith: { first, _ in first })
        return content.pins.filter { isActive(day: $0.day) }.flatMap { pin in legs[pin.id] ?? [pin.coordinate] }
    }

    /// A settle wider than this many times the framing asked for is MapKit's default camera, not the pane's shape.
    private static let worldFactor = 8.0
    private static let maxCorrections = 3
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
    private func apply(_ request: CameraRequest, animated: Bool, force: Bool = false) {
        guard force || request.id != appliedRequest else { return }
        appliedRequest = request.id
        // One owner for the camera, and it never fights the user: a request that arrives while a pan, zoom or compass
        // gesture is still settling is dropped (the next explicit day choice or selection frames again).
        if userInteracted, animated {
            IterPerf.count("trip.cameraRequestDropped")
            return
        }
        IterPerf.count("trip.cameraRequestApplied")
        let target: GeoRegion
        switch request.kind {
        case .fit(let r), .pan(let r): target = r
        }
        framed = target
        corrections = 0
        // Assigning the region the binding already holds does nothing, so a re-application of it is nudged.
        var framing = Self.mkRegion(target)
        if case .fit = request.kind { framing = fitted(framing) }
        let region = Self.distinct(framing, from: position)
        if animated {
            withAnimation(.smooth) { position = .region(region) }
        } else {
            position = .region(region)
        }
    }
}

// MARK: - Pin

/// A numbered pin. Equatable on what it draws, so a selection or a day change rebuilds only the pins whose look changes.
private struct TripPinView: View, Equatable {
    let number: Int
    let name: String
    let selected: Bool
    let inDay: Bool

    /// Pins of days that are not selected.
    private static let dimmedOpacity = 0.55

    var body: some View {
        let _ = IterPerf.count("trip.pinBody")
        let size = selected ? IterSize.mapPinSelected : IterSize.mapPin
        Text(number, format: .number)
            .font(IterFont.captionStrong)
            .monospacedDigit()
            .foregroundStyle(inDay ? IterColor.onAccent : IterColor.backgroundWindow)
            .frame(width: size, height: size)
            .background(inDay ? IterColor.accentEmphasis : IterColor.mapPinInactive, in: Circle())
            .overlay(Circle().strokeBorder(IterColor.backgroundWindow, lineWidth: selected ? IterStroke.thick : IterStroke.thin))
            .opacity(inDay || selected ? 1 : Self.dimmedOpacity)
            .accessibilityLabel(Text("Stop \(number), \(name)", comment: "VoiceOver: map pin"))
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
            // System glass buttons; the container lets the three pieces read as one control.
            GlassEffectContainer(spacing: IterSpace.xs) {
                HStack(spacing: IterSpace.xs) {
                    Button { step(-1) } label: { Label(String(localized: "Previous day", comment: "Accessibility label"), systemImage: "chevron.left") }
                        .labelStyle(.iconOnly)
                        .buttonBorderShape(.circle)
                        .help(Text("Previous day", comment: "Tooltip"))
                    Menu {
                        Button(String(localized: "All Days", comment: "Map day switcher: show every day")) { selectedDay = nil }
                        Divider()
                        ForEach(days, id: \.index) { day in
                            Button(TimeText.daySwitcher(index: day.index, day: day.date)) { selectedDay = day.index }
                        }
                    } label: {
                        Text(title).monospacedDigit().frame(minWidth: 150)
                    }
                    .menuStyle(.button)
                    .menuIndicator(.hidden)
                    .buttonBorderShape(.capsule)
                    .fixedSize()
                    .help(Text("Choose the day shown on the map", comment: "Tooltip"))
                    Button { step(1) } label: { Label(String(localized: "Next day", comment: "Accessibility label"), systemImage: "chevron.right") }
                        .labelStyle(.iconOnly)
                        .buttonBorderShape(.circle)
                        .help(Text("Next day", comment: "Tooltip"))
                }
                .buttonStyle(.glass)
                .controlSize(.large)
            }
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
