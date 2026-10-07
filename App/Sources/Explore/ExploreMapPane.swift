import SwiftUI
import MapKit
import AppKit
import IterCore
import IterData
import IterDesign
import IterFeatures

/// The map: pins with hierarchy, one selection shared with the list (the selected pin is the only mark of it here;
/// the place itself opens in the list column), and Add Spot mode.
struct ExploreMapPane: View {
    @Bindable var explore: ExploreModel
    @Environment(\.renderMode) private var renderMode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppModel.self) private var app
    @State private var position: MapCameraPosition
    /// True once the map wrote a user-positioned `position` (pan, zoom, stepper, compass) that has not settled yet.
    @State private var userInteracted = false
    @State private var appliedRequest = 0
    @State private var paneSize = CGSize.zero

    init(explore: ExploreModel) {
        self.explore = explore
        // Start framed, so MapKit never shows (and reports) its automatic world camera.
        if let r = explore.initialCameraRegion {
            _position = State(initialValue: .region(Self.mkRegion(r)))
        } else {
            _position = State(initialValue: .automatic)
        }
    }

    var body: some View {
        let _ = IterPerf.count("map.paneBody")
        ZStack {
            if renderMode == .snapshot {
                ExploreMapStandIn(explore: explore)
            } else if paneSize.width > 0, paneSize.height > 0 {
                // Created only once the pane has a real size: a map framed before layout settles on MapKit's own
                // default camera, not our region.
                liveMap
            } else {
                Color.clear
            }
        }
        // MapKit's Map extends itself under the toolbar; clip it to the safe area so the bar is one plain strip.
        .clipped()
        .overlay(alignment: .top) {
            if explore.isAddingSpot {
                AddSpotBanner { explore.isAddingSpot = false }
                    .padding(IterSpace.md)
            }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: {
            paneSize = $0
            explore.setMapViewport($0)
        }
    }

    // MARK: Live map

    private var mapSelection: Binding<String?> {
        Binding(get: { explore.selectedID },
                set: { if !explore.isAddingSpot { explore.select($0, from: .map) } })
    }

    private var liveMap: some View {
        MapReader { proxy in
            Map(position: $position, selection: mapSelection) {
                // The model hands over the items ordered and clustered (MapKit has no z-index: later annotations draw
                // on top, so the selected pin is last); nothing is sorted or computed here.
                ForEach(explore.mapItems) { item in
                    switch item {
                    case .pin(let pin): pinAnnotation(pin)
                    case .cluster(let cluster): clusterAnnotation(cluster)
                    }
                }
                UserLocationMapContent(location: app.location)
                if let draft = explore.draftCoordinate {
                    Annotation(String(localized: "New spot", comment: "Map pin label"), coordinate: clCoordinate(draft), anchor: .bottom) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.title)
                            .foregroundStyle(IterColor.mapPin)
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
            .mapControls {
                if app.location.showsSystemIndicator { MapUserLocationButton() }
                MapZoomStepper()
                MapCompass()
                MapScaleView()
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                IterPerf.once("map.firstSettle")
                IterPerf.mark("map.settle")
                let r = context.region
                // A settle is the user's only when the map wrote a user-positioned value into `position` (see
                // `.onChange(of: position)`); layout and aspect settles MapKit makes on its own never are.
                let byUser = userInteracted
                userInteracted = false
                explore.cameraDidChange(to: GeoRegion(center: Coordinate(latitude: r.center.latitude, longitude: r.center.longitude),
                                                      latitudeDelta: r.span.latitudeDelta, longitudeDelta: r.span.longitudeDelta),
                                        byUser: byUser)
            }
            .onChange(of: position) { _, new in
                if new.positionedByUser { userInteracted = true }
            }
            .simultaneousGesture(SpatialTapGesture().onEnded { tap in
                guard explore.isAddingSpot, let c = proxy.convert(tap.location, from: .local) else { return }
                explore.dropPin(at: Coordinate(latitude: c.latitude, longitude: c.longitude))
            })
            .onContinuousHover { phase in
                switch phase {
                case .active: if explore.isAddingSpot { NSCursor.crosshair.set() }
                case .ended: NSCursor.arrow.set()
                }
            }
        }
        .onChange(of: explore.cameraRequest) { _, request in
            if let request { apply(request, animated: !reduceMotion) }
        }
        .onAppear {
            IterPerf.once("map.created")
            if let request = explore.cameraRequest { apply(request, animated: false) }
        }
    }

    private func pinAnnotation(_ pin: ExplorePin) -> some MapContent {
        let anchor: UnitPoint = pin.style == .selected ? .bottom : .center
        return Annotation(pin.name, coordinate: clCoordinate(pin.coordinate), anchor: anchor) {
            pinBody(pin)
        }
        .tag(pin.id)
        .annotationTitles(.hidden)
    }

    private func clusterAnnotation(_ cluster: ExploreCluster) -> some MapContent {
        Annotation(LightText.clusterDescription(count: cluster.count), coordinate: clCoordinate(cluster.coordinate), anchor: .center) {
            Button { explore.zoomToCluster(cluster.id) } label: { ExploreClusterView(cluster: cluster) }
                .buttonStyle(.plain)
                .allowsHitTesting(!explore.isAddingSpot)
        }
        .annotationTitles(.hidden)
    }

    private func pinBody(_ pin: ExplorePin) -> some View {
        ExplorePinView(pin: pin)
            .allowsHitTesting(!explore.isAddingSpot)
            .onHover { inside in
                if inside { explore.hoveredID = pin.id } else if explore.hoveredID == pin.id { explore.hoveredID = nil }
            }
            .contextMenu {
                // The menu needs the whole spot; the pin carries only what it draws, so it is looked up when the menu opens.
                if let row = explore.row(id: pin.id) {
                    ExploreSpotMenu(spot: row.spot, day: row.day ?? LocalDay.today(in: row.spot.timeZone))
                }
            }
    }

    private func apply(_ request: CameraRequest, animated: Bool) {
        guard request.id != appliedRequest else { return }
        appliedRequest = request.id
        let target: GeoRegion
        switch request.kind {
        case .fit(let r), .pan(let r): target = r
        }
        // The model keeps automatic fits within `MapCameraPolicy.maxAutomaticSpan`; this only guards MapKit's limits.
        let region0 = Self.mkRegion(target)
        // Assigning the region the binding already holds does nothing, so a re-application of it is nudged.
        let region = Self.distinct(region0, from: position)
        if animated {
            withAnimation(.smooth) { position = .region(region) }
        } else {
            position = .region(region)
        }
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
                           span: MKCoordinateSpan(latitudeDelta: min(target.latitudeDelta, 120),
                                                  longitudeDelta: min(target.longitudeDelta, 300)))
    }

    private func clCoordinate(_ c: Coordinate) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: c.latitude, longitude: c.longitude)
    }
}

/// The user's position on a live map: MapKit's own blue dot for a real, permitted location; for a simulated one
/// (`-IterLocation`), which MapKit cannot know, an equivalent dot at the simulated coordinate. Nothing otherwise.
struct UserLocationMapContent: MapContent {
    let location: UserLocationModel

    var body: some MapContent {
        if location.showsSystemIndicator {
            UserAnnotation()
        }
        if let c = location.simulatedIndicatorCoordinate {
            Annotation(String(localized: "Your location (simulated)", comment: "Map: the simulated user location"),
                       coordinate: CLLocationCoordinate2D(latitude: c.latitude, longitude: c.longitude), anchor: .center) {
                SimulatedUserLocationDot()
            }
            .annotationTitles(.hidden)
        }
    }
}

/// A system-style location dot: blue, white ring, soft shadow.
struct SimulatedUserLocationDot: View {
    var body: some View {
        Circle()
            .fill(IterColor.userLocation)
            .frame(width: 14, height: 14)
            .overlay(Circle().strokeBorder(.white, lineWidth: 2.5))
            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
            .accessibilityElement()
            .accessibilityLabel(Text("Your location (simulated)", comment: "VoiceOver: the simulated user location on the map"))
    }
}

/// The hint shown while Add Spot mode is on.
struct AddSpotBanner: View {
    var onCancel: () -> Void
    @Environment(\.renderMode) private var renderMode

    var body: some View {
        HStack(spacing: IterSpace.sm) {
            Image(systemName: "mappin.and.ellipse").foregroundStyle(IterColor.accent)
            Text("Click the map to drop a pin for your spot", comment: "Hint banner while Add Spot mode is on")
                .font(IterFont.subheadline)
            Button(String(localized: "Cancel", comment: "Button")) { onCancel() }
                .keyboardShortcut(.cancelAction)
                .help(String(localized: "Leave Add Spot (Esc)", comment: "Tooltip"))
        }
        .padding(.horizontal, IterSpace.md)
        .padding(.vertical, IterSpace.sm)
        .background(renderMode == .snapshot ? AnyShapeStyle(IterColor.backgroundContent) : AnyShapeStyle(.regularMaterial),
                    in: Capsule())
        .overlay(Capsule().strokeBorder(IterColor.accent, lineWidth: IterStroke.thin))
        .accessibilityElement(children: .combine)
    }
}

/// Snapshot renders cannot draw a live map. This draws the same pins, with the same pin views, on a flat ground
/// at the framed region, so hierarchy and legibility can be reviewed.
struct ExploreMapStandIn: View {
    @Bindable var explore: ExploreModel
    @Environment(AppModel.self) private var app

    var body: some View {
        GeometryReader { geo in
            let region = MapCameraPolicy.fit(explore.fitCoordinates)
            ZStack(alignment: .topLeading) {
                Rectangle().fill(IterColor.backgroundControl)
                if let region {
                    ForEach(explore.mapItems) { item in
                        switch item {
                        case .pin(let pin): ExplorePinView(pin: pin).position(project(pin.coordinate, region, geo.size))
                        case .cluster(let cluster): ExploreClusterView(cluster: cluster).position(project(cluster.coordinate, region, geo.size))
                        }
                    }
                    if let draft = explore.draftCoordinate {
                        Image(systemName: "mappin.circle.fill").font(.title).foregroundStyle(IterColor.mapPin)
                            .position(project(draft, region, geo.size))
                    }
                    if let c = app.location.simulatedIndicatorCoordinate {
                        SimulatedUserLocationDot().position(project(c, region, geo.size))
                    }
                }
                Text("Map (snapshot stand-in)", comment: "Label on the static map used in snapshot renders")
                    .font(IterFont.caption)
                    .foregroundStyle(IterColor.textTertiary)
                    .padding(IterSpace.sm)
            }
        }
        .accessibilityHidden(true)
    }

    private func project(_ c: Coordinate, _ r: GeoRegion, _ size: CGSize) -> CGPoint {
        let x = (c.longitude - (r.center.longitude - r.longitudeDelta / 2)) / r.longitudeDelta
        let y = ((r.center.latitude + r.latitudeDelta / 2) - c.latitude) / r.latitudeDelta
        return CGPoint(x: x * size.width, y: y * size.height)
    }
}
