import SwiftUI
import MapKit
import IterCore
import IterDesign
import IterFeatures

/// The full-bleed Explore map for iPhone and iPad: pins and clusters from the model, the user's location, camera
/// requests in, viewport and region out. Floating glass controls sit top trailing.
struct ExploreMapLayer: View {
    @Bindable var explore: ExploreModel
    /// What covers the bottom of the map (the sheet at its resting detent); the camera frames the rest.
    var bottomInset: CGFloat = 0
    /// What covers the leading edge (the iPad panel column).
    var leadingInset: CGFloat = 0
    /// A pin was tapped (selected, panel open).
    var onPinSelected: () -> Void = {}

    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.renderMode) private var renderMode
    @State private var position: MapCameraPosition
    @State private var userInteracted = false
    @State private var appliedRequest = 0
    @State private var mapSize = CGSize.zero
    @AppStorage(MapStyleChoice.storageKey) private var mapStyleRaw = MapStyleChoice.default.rawValue
    @State private var daylight = DaylightClock()
    @AppStorage(DaylightClock.storageKey) private var showsDaylight = true

    init(explore: ExploreModel, bottomInset: CGFloat = 0, leadingInset: CGFloat = 0, onPinSelected: @escaping () -> Void = {}) {
        self.explore = explore
        self.bottomInset = bottomInset
        self.leadingInset = leadingInset
        self.onPinSelected = onPinSelected
        // `-IterMapCamera` (screenshots): start there and ignore the model's fit requests.
        if let launch = AppLaunch.mapCamera {
            _position = State(initialValue: .camera(MapCamera(
                centerCoordinate: CLLocationCoordinate2D(latitude: launch.coordinate.latitude, longitude: launch.coordinate.longitude),
                distance: launch.distanceMetres, heading: 0, pitch: launch.pitch)))
        } else if let r = explore.initialCameraRegion {
            _position = State(initialValue: .region(Self.mkRegion(r)))
        } else {
            _position = State(initialValue: .automatic)
        }
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                if renderMode == .snapshot {
                    ExploreMapLayerStandIn(explore: explore)
                } else if mapSize.width > 0, mapSize.height > 0 {
                    liveMap
                } else {
                    Color(IterColor.backgroundWindow)
                }
            }
            .ignoresSafeArea()
            .onGeometryChange(for: CGSize.self) { $0.size } action: {
                mapSize = $0
                explore.setMapViewport($0)
            }
            controls
        }
    }

    // MARK: Controls

    private var controls: some View {
        // Map style and your location share one glass capsule, as in Maps.
        GlassEffectContainer {
        VStack(spacing: 0) {
            MapStyleMenu(isGlass: false)
            Button { locate() } label: { MapControlLabel(systemImage: "location") }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Show my location", comment: "Map control"))
                .accessibilityHint(app.location.coordinate == nil ? Text("Asks to use your location", comment: "VoiceOver hint") : Text(verbatim: ""))
        }
        .glassEffect(.regular.interactive(), in: .capsule)
        }
        .padding(.trailing, IterSpace.lg)
        .padding(.top, IterSpace.sm)
    }

    private func locate() {
        guard let c = app.location.coordinate else { app.location.start(); return }
        withAnimation(.smooth) {
            position = .region(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: c.latitude, longitude: c.longitude),
                                                  span: MKCoordinateSpan(latitudeDelta: 0.3, longitudeDelta: 0.3)))
        }
    }

    // MARK: Map

    private var mapSelection: Binding<String?> {
        Binding(get: { explore.selectedID }, set: { id in
            explore.select(id, from: .map)
            if id != nil { onPinSelected() }
        })
    }

    private var style: MapStyle { MapStyleChoice(stored: mapStyleRaw).mapStyle() }

    private var liveMap: some View {
        MapReader { proxy in map(proxy) }
    }

    private func map(_ proxy: MapProxy) -> some View {
        Map(position: $position, bounds: .globe, selection: mapSelection) {
            if daylight.isShown(isOn: showsDaylight, style: MapStyleChoice(stored: mapStyleRaw)) { DaylightOverlay(daylight.shading) }
            ForEach(explore.mapItems) { item in
                switch item {
                case .pin(let pin):
                    if pin.id != explore.adjusting?.id {
                        if explore.canMove(pin.id), pin.style == .selected || explore.dragging?.id == pin.id { pointAnnotation(pin) }
                        pinAnnotation(pin, proxy: proxy)
                    }
                case .cluster(let cluster): clusterAnnotation(cluster)
                }
            }
            if app.location.showsSystemIndicator { UserAnnotation() }
            if let c = app.location.simulatedIndicatorCoordinate {
                Annotation(String(localized: "Your location", comment: "Map: the user's location"),
                           coordinate: CLLocationCoordinate2D(latitude: c.latitude, longitude: c.longitude), anchor: .center) {
                    Circle().fill(IterColor.userLocation).frame(width: 14, height: 14)
                        .overlay(Circle().strokeBorder(.white, lineWidth: 2.5))
                        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(style)
        .daylightClock(daylight)
        .mapControls { MapCompass() }
        .safeAreaPadding(.bottom, bottomInset)
        .safeAreaPadding(.leading, leadingInset)
        .onMapCameraChange(frequency: .onEnd) { context in
            let r = context.region
            let byUser = userInteracted
            userInteracted = false
            explore.cameraDidChange(to: GeoRegion(center: Coordinate(latitude: r.center.latitude, longitude: r.center.longitude),
                                                  latitudeDelta: r.span.latitudeDelta, longitudeDelta: r.span.longitudeDelta),
                                    byUser: byUser)
        }
        .onChange(of: position) { _, new in
            if new.positionedByUser { userInteracted = true }
        }
        .onMapCameraChange(frequency: .continuous) { context in
            guard explore.adjusting != nil else { return }
            let c = context.camera.centerCoordinate
            explore.adjustCenterChanged(Coordinate(latitude: c.latitude, longitude: c.longitude))
        }
        .overlay {
            if explore.adjusting != nil {
                // The crosshair is the spot: the map pans under it, and Done saves the coordinate beneath it.
                Image(systemName: "plus")
                    .font(.system(size: IterSize.iconLarge, weight: .light))
                    .foregroundStyle(IterColor.mapPin)
                    .shadow(radius: IterStroke.regular)
                    .padding(.bottom, bottomInset)
                    .padding(.leading, leadingInset)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .onChange(of: explore.adjusting?.id) { _, id in
            guard id != nil, let session = explore.adjusting else { return }
            let span = explore.visibleRegion.map { MKCoordinateSpan(latitudeDelta: $0.latitudeDelta, longitudeDelta: $0.longitudeDelta) }
                ?? MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            withAnimation(reduceMotion ? nil : .smooth) {
                position = .region(MKCoordinateRegion(center: clCoordinate(session.original), span: span))
            }
        }
        .onChange(of: explore.cameraRequest) { _, request in
            if let request { apply(request, animated: !reduceMotion) }
        }
        .onAppear {
            if let request = explore.cameraRequest { apply(request, animated: false) }
        }
    }

    private func pinAnnotation(_ pin: ExplorePin, proxy: MapProxy) -> some MapContent {
        let anchor = UnitPoint(x: MapPinAnchor.horizontal, y: MapPinAnchor.vertical(for: pin.style))
        let movable = explore.adjusting == nil && !explore.isAddingSpot && explore.canMove(pin.id)
        let at = explore.displayCoordinate(for: pin.id, stored: pin.coordinate)
        return Annotation(pin.name, coordinate: clCoordinate(at), anchor: anchor) {
            ExplorePinView(pin: pin)
                // Touch and hold, then drag (lift, haptic and the rest are the shared modifier's).
                .ownPinDrag(id: pin.id, stored: pin.coordinate, host: explore, proxy: proxy, isEnabled: movable)
                .contextMenu {
                    if let row = explore.row(id: pin.id) {
                        ExploreSpotMenu(spot: row.spot, day: row.day ?? LocalDay.today(in: row.spot.timeZone))
                    }
                }
        }
        .tag(pin.id)
        .annotationTitles(.hidden)
    }

    /// The exact point of a spot of yours that is selected or being carried: the pin's pointer ends here, so the place is
    /// never read off the unit.
    private func pointAnnotation(_ pin: ExplorePin) -> some MapContent {
        Annotation("", coordinate: clCoordinate(explore.displayCoordinate(for: pin.id, stored: pin.coordinate)), anchor: .center) {
            PinTipDot()
        }
        .annotationTitles(.hidden)
    }

    private func clusterAnnotation(_ cluster: ExploreCluster) -> some MapContent {
        Annotation(LightText.clusterDescription(count: cluster.count), coordinate: clCoordinate(cluster.coordinate), anchor: .center) {
            Button { explore.zoomToCluster(cluster.id) } label: { ExploreClusterView(cluster: cluster) }
                .buttonStyle(.plain)
        }
        .annotationTitles(.hidden)
    }

    private func apply(_ request: CameraRequest, animated: Bool) {
        guard request.id != appliedRequest, AppLaunch.mapCamera == nil else { return }
        appliedRequest = request.id
        let target: GeoRegion
        switch request.kind { case .fit(let r), .pan(let r): target = r }
        let region = Self.distinct(Self.mkRegion(target), from: position)
        if animated { withAnimation(.smooth) { position = .region(region) } } else { position = .region(region) }
    }

    private static func distinct(_ region: MKCoordinateRegion, from position: MapCameraPosition) -> MKCoordinateRegion {
        guard let current = position.region,
              abs(current.center.latitude - region.center.latitude) < 1e-9,
              abs(current.span.latitudeDelta - region.span.latitudeDelta) < 1e-9 else { return region }
        return MKCoordinateRegion(center: region.center,
                                  span: MKCoordinateSpan(latitudeDelta: region.span.latitudeDelta * 1.00001,
                                                         longitudeDelta: region.span.longitudeDelta))
    }

    private static func mkRegion(_ target: GeoRegion) -> MKCoordinateRegion {
        MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: target.center.latitude, longitude: target.center.longitude),
                           span: MKCoordinateSpan(latitudeDelta: min(target.latitudeDelta, 120), longitudeDelta: min(target.longitudeDelta, 300)))
    }

    private func clCoordinate(_ c: Coordinate) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: c.latitude, longitude: c.longitude)
    }
}
