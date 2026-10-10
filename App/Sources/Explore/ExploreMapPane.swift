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
    /// What covers the map: the toolbar above it and the panel floating over its leading edge.
    var insets = EdgeInsets()
    @Namespace private var mapScope
    @Environment(\.renderMode) private var renderMode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(MapStyleChoice.storageKey) private var mapStyleRaw = MapStyleChoice.default.rawValue
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL
    @State private var position: MapCameraPosition
    /// True once the map wrote a user-positioned `position` (pan, zoom, stepper, compass) that has not settled yet.
    @State private var userInteracted = false
    @State private var appliedRequest = 0
    @State private var dragGrab = CGSize.zero
    @State private var dragTipBefore: CGPoint?
    /// The pane's top-left in window coordinates (the probe and nothing else reads it).
    @State private var paneOrigin = CGPoint.zero
    @State private var paneSize = CGSize.zero
    /// The pane's size reaches the model (for clustering) once a resize is still; the first size is taken at once.
    @State private var resizeDebounce = TrailingDebouncer(delay: .milliseconds(120))
    @State private var daylight = DaylightClock()
    @AppStorage(DaylightClock.storageKey) private var showsDaylight = true

    init(explore: ExploreModel, insets: EdgeInsets = EdgeInsets()) {
        self.explore = explore
        self.insets = insets
        // Start framed, so MapKit never shows (and reports) its automatic world camera.
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
        .overlay(alignment: .top) {
            if explore.adjusting != nil {
                AdjustLocationBanner()
                    .padding(IterSpace.md)
                    .padding(.top, insets.top)
                    .padding(.leading, insets.leading)
            } else if explore.isAddingSpot {
                AddSpotBanner { explore.isAddingSpot = false }
                    .padding(IterSpace.md)
                    .padding(.top, insets.top)
                    .padding(.leading, insets.leading)
            }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
            if paneSize == .zero {
                paneSize = size
                explore.setMapViewport(size)
            } else {
                // Only the model needs later sizes (clustering); `paneSize` just says the pane has had one.
                resizeDebounce.schedule { explore.setMapViewport(size) }
            }
        }
        .onGeometryChange(for: CGPoint.self) { $0.frame(in: .global).origin } action: { paneOrigin = $0 }
    }

    // MARK: Live map

    private var mapSelection: Binding<String?> {
        Binding(get: { explore.selectedID },
                set: { new in
                    guard !explore.isAddingSpot else { return }
                    // MapKit clears a selected pin when it is clicked; for a spot of yours that click starts "click it, then
                    // drag it", so it stays selected. A click on empty map (no pin hovered) still clears.
                    if PinDrag.keepsSelection(writing: new, selectedID: explore.selectedID, hoveredID: explore.hoveredID,
                                              selectedIsMovable: explore.selectedID.map { explore.canMove($0) } ?? false) { return }
                    explore.select(new, from: .map)
                })
    }

    private var liveMap: some View {
        MapReader { proxy in
            Map(position: $position, bounds: .globe, selection: mapSelection, scope: mapScope) {
                if daylight.isShown(isOn: showsDaylight, style: MapStyleChoice(stored: mapStyleRaw)) { DaylightOverlay(daylight.shading) }
                // The model hands over the items ordered and clustered (MapKit has no z-index: later annotations draw
                // on top, so the selected pin is last); nothing is sorted or computed here.
                ForEach(explore.mapItems) { item in
                    switch item {
                    case .pin(let pin):
                        if pin.id != explore.adjusting?.id {
                            if pin.style == .selected || explore.dragging?.id == pin.id, explore.canMove(pin.id) { pointAnnotation(pin) }
                            pinAnnotation(pin, proxy: proxy)
                        }
                    case .cluster(let cluster): clusterAnnotation(cluster)
                    }
                }
                UserLocationMapContent(location: app.location)
                if let draft = explore.draftCoordinate {
                    Annotation(String(localized: "New spot", comment: "Map pin label"), coordinate: clCoordinate(draft), anchor: .center) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.title)
                            .foregroundStyle(IterColor.mapPin)
                    }
                }
            }
            .mapStyle(MapStyleChoice(stored: mapStyleRaw).mapStyle())
            .daylightClock(daylight)
            .mapControls { MapScaleView() }
            .safeAreaPadding(insets)
            .overlay(alignment: .topTrailing) {
                MapControlStack(scope: mapScope, locate: app.location.showsSystemIndicator ? { locate() } : nil) {
                    MapControlButton(title: String(localized: "Windy", comment: "Map control: open the map area on windy.com"),
                                     systemImage: "wind",
                                     help: String(localized: "Open this map area on windy.com", comment: "Tooltip")) {
                        if let region = explore.visibleRegion {
                            openURL(WindyLink.url(center: region.center, zoom: WindyLink.zoom(forLatitudeDelta: region.latitudeDelta)))
                        }
                    }
                    .disabled(explore.visibleRegion == nil)
                    MapControlButton(title: String(localized: "Add Spot", comment: "Map control: click the map to add your own spot"),
                                     systemImage: "mappin.and.ellipse",
                                     help: String(localized: "Add your own spot: click the map to drop a pin (Esc to cancel)", comment: "Tooltip"),
                                     isOn: explore.isAddingSpot) {
                        explore.isAddingSpot.toggle()
                    }
                }
                    .padding(.top, insets.top)
            }
            .mapScope(mapScope)
            .onMapCameraChange(frequency: .onEnd) { context in
                if AppLaunch.convertProbe { runConvertProbe(proxy, context.camera) }
                if PinDragProbe.shared.isOn {
                    PinDragProbe.shared.cameraSettled(context.camera); probeSpot(proxy)
                    if explore.adjusting != nil {
                        // Where the crosshair is drawn (the padded area's centre, in window space) and what is under it.
                        let at = CGPoint(x: paneOrigin.x + insets.leading + (paneSize.width - insets.leading - insets.trailing) / 2,
                                         y: paneOrigin.y + insets.top + (paneSize.height - insets.top - insets.bottom) / 2)
                        if let c = proxy.convert(at, from: .global) { PinDragProbe.shared.note("crosshair", ["lat": c.latitude, "lon": c.longitude]) }
                    }
                }
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
                        .padding(insets)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .onChange(of: explore.selectedID) { _, selected in
                guard PinDragProbe.shared.isOn else { return }
                PinDragProbe.shared.note("selectedID", selected ?? "")
                Task { try? await Task.sleep(for: .milliseconds(600)); probeSpot(proxy) }
            }
            .onChange(of: explore.adjusting == nil) { _, _ in
                guard PinDragProbe.shared.isOn else { return }
                Task { try? await Task.sleep(for: .milliseconds(600)); probeSpot(proxy) }
            }
            .onChange(of: explore.adjusting?.id) { _, id in
                // Entering Adjust Location: bring the spot to the middle, keeping the zoom.
                guard id != nil, let session = explore.adjusting else { return }
                let span = explore.visibleRegion.map { MKCoordinateSpan(latitudeDelta: $0.latitudeDelta, longitudeDelta: $0.longitudeDelta) }
                    ?? MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                withAnimation(reduceMotion ? nil : .smooth) {
                    position = .region(MKCoordinateRegion(center: clCoordinate(session.original), span: span))
                }
            }
            .simultaneousGesture(SpatialTapGesture(coordinateSpace: .global).onEnded { tap in
                // Window coordinates on both sides: the map's own `.local` space starts inside the safe-area padding
                // (the floating card and toolbar), so a tap read in the pane's space landed that far down and across.
                guard explore.isAddingSpot, let c = proxy.convert(tap.location, from: .global) else { return }
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

    /// Debug aid (`-IterConvertProbe`): converts a grid of screen points to coordinates and back, and the camera centre to
    /// a screen point, and logs the errors in metres and points. A wrong conversion would show as a large error.
    private func runConvertProbe(_ proxy: MapProxy, _ camera: MapCamera) {
        let size = paneSize
        var worst = 0.0
        var lines: [String] = []
        for fx in [0.25, 0.5, 0.75] {
            for fy in [0.25, 0.5, 0.75] {
                let point = CGPoint(x: size.width * fx, y: size.height * fy)
                guard let c = proxy.convert(point, from: .local) else { lines.append("(\(fx),\(fy)) nil"); continue }
                let back = proxy.convert(c, to: .local) ?? .zero
                let err = hypot(back.x - point.x, back.y - point.y)
                worst = max(worst, err)
                lines.append(String(format: "(%.2f,%.2f) -> %.5f,%.5f -> back %.2f pt off", fx, fy, c.latitude, c.longitude, err))
            }
        }
        let centre = proxy.convert(camera.centerCoordinate, to: .local) ?? .zero
        let centreGlobal = proxy.convert(camera.centerCoordinate, to: .global) ?? .zero
        // A pane point read both ways: as a window point (what a tap reports) and as a map-local point shifted by the insets.
        var worstSpace = 0.0
        for (fx, fy) in [(0.3, 0.3), (0.6, 0.7), (0.9, 0.2)] {
            let p = CGPoint(x: size.width * fx, y: size.height * fy)
            let viaGlobal = proxy.convert(CGPoint(x: paneOrigin.x + p.x, y: paneOrigin.y + p.y), from: .global)
            let viaLocal = proxy.convert(CGPoint(x: p.x - insets.leading, y: p.y - insets.top), from: .local)
            if let a = viaGlobal, let b = viaLocal {
                worstSpace = max(worstSpace, Coordinate(latitude: a.latitude, longitude: a.longitude).distance(to: Coordinate(latitude: b.latitude, longitude: b.longitude)))
            }
            let naive = proxy.convert(p, from: .local)
            if let a = viaGlobal, let n = naive {
                lines.append(String(format: "tap at pane (%.0f,%.0f): window-space coordinate vs naive-local coordinate differ by %.0f m", p.x, p.y,
                                    Coordinate(latitude: a.latitude, longitude: a.longitude).distance(to: Coordinate(latitude: n.latitude, longitude: n.longitude))))
            }
        }
        var report = String(format: "ConvertProbe: pane %.0fx%.0f pitch %.0f distance %.0f m; camera centre at (%.1f, %.1f) pt, padded-area centre (%.1f, %.1f); worst round trip %.3f pt; camera centre in window space (%.1f, %.1f), expected (%.1f, %.1f); global vs inset-shifted local differ by %.2f m\n",
              size.width, size.height, camera.pitch, camera.distance, centre.x, centre.y,
              insets.leading + (size.width - insets.leading - insets.trailing) / 2, insets.top + (size.height - insets.top - insets.bottom) / 2, worst,
              centreGlobal.x, centreGlobal.y, paneOrigin.x + insets.leading + (size.width - insets.leading - insets.trailing) / 2,
              paneOrigin.y + insets.top + (size.height - insets.top - insets.bottom) / 2, worstSpace)
        for line in lines { report += "ConvertProbe:   \(line)\n" }
        AppLaunch.log.notice("\(report, privacy: .public)")
        try? report.write(toFile: NSTemporaryDirectory() + "iter-convert-probe.txt", atomically: true, encoding: .utf8)
    }

    private func locate() {
        withAnimation(reduceMotion ? nil : .smooth) { position = .userLocation(fallback: position) }
    }

    private func pinAnnotation(_ pin: ExplorePin, proxy: MapProxy) -> some MapContent {
        let anchor = UnitPoint(x: MapPinAnchor.horizontal, y: MapPinAnchor.vertical(for: pin.style))
        // Every spot of yours drags, selected or not (a press on an unselected one selects it first).
        let movable = !explore.isAddingSpot && explore.adjusting == nil && explore.canMove(pin.id)
        let lifted = explore.dragging?.id == pin.id
        let at = explore.displayCoordinate(for: pin.id, stored: pin.coordinate)
        return Annotation(pin.name, coordinate: clCoordinate(at), anchor: anchor) {
            pinBody(pin)
                // Held pins rise a little, with a soft shadow; only the drawing rises, the coordinate stays the tip's.
                .shadow(color: .black.opacity(lifted ? 0.3 : 0), radius: lifted ? 4 : 0, y: lifted ? 3 : 0)
                .offset(y: lifted ? -PinDrag.liftPoints : 0)
                .animation(reduceMotion ? nil : .smooth, value: lifted)
                .pointerStyle(movable ? (lifted ? .grabActive : .grabIdle) : nil)
                .gesture(pinDrag(pin, proxy: proxy), isEnabled: movable)
                .help(movable ? String(localized: "Drag to move your spot", comment: "Tooltip") : "")
        }
        .tag(pin.id)
        .annotationTitles(.hidden)
    }

    /// The exact point of a selected spot of yours: the pin's pointer ends here, so the place is never read off the unit.
    private func pointAnnotation(_ pin: ExplorePin) -> some MapContent {
        Annotation("", coordinate: clCoordinate(explore.displayCoordinate(for: pin.id, stored: pin.coordinate)), anchor: .center) {
            Circle()
                .fill(IterColor.mapPin)
                .frame(width: IterSpace.sm, height: IterSpace.sm)
                .overlay(Circle().strokeBorder(IterColor.separator, lineWidth: IterStroke.hairline))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .annotationTitles(.hidden)
    }

    /// Drags one of your own spots. The point under the cursor keeps its place relative to the pin's tip, so the pin does
    /// not jump to the cursor; the coordinate is converted from the global space the gesture reports in.
    private func pinDrag(_ pin: ExplorePin, proxy: MapProxy) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .global)
            .onChanged { value in
                if explore.dragging == nil {
                    guard explore.beginDrag(pin.id) else { return }
                    let tip = proxy.convert(clCoordinate(pin.coordinate), to: .global) ?? value.startLocation
                    dragGrab = PinDrag.grab(pointer: value.startLocation, tip: tip)
                    dragTipBefore = tip
                }
                let point = PinDrag.tipPoint(pointer: value.location, grab: dragGrab)
                if let c = proxy.convert(point, from: .global) {
                    explore.drag(to: Coordinate(latitude: c.latitude, longitude: c.longitude))
                }
            }
            .onEnded { value in
                let drop = PinDrag.tipPoint(pointer: value.location, grab: dragGrab)
                let expected = proxy.convert(drop, from: .global).map { Coordinate(latitude: $0.latitude, longitude: $0.longitude) }
                let delta = CGSize(width: value.location.x - value.startLocation.x, height: value.location.y - value.startLocation.y)
                let id = pin.id
                explore.endDrag(commit: true)
                if PinDragProbe.shared.isOn, let stored = explore.row(id: id)?.spot.coordinate {
                    PinDragProbe.shared.moveCommitted(stored: stored, expected: expected, delta: delta, tipBefore: dragTipBefore, proxy: proxy)
                    Task {
                        try? await Task.sleep(for: .milliseconds(500))
                        PinDragProbe.shared.tipAfterDrop(stored: stored, proxy: proxy)
                        probeSpot(proxy)
                    }
                }
            }
    }

    /// `-IterPinDragProbe`: reports the selected spot of yours (see `PinDragProbe`).
    private func probeSpot(_ proxy: MapProxy) {
        guard let id = explore.selectedID.flatMap({ explore.canMove($0) ? $0 : nil }) ?? PinDragProbe.shared.lastID,
              let row = explore.row(id: id) else { return }
        var style = "none"
        for case .pin(let pin) in explore.mapItems where pin.id == id { style = "\(pin.style)" }
        PinDragProbe.shared.spotShown(id: id, coordinate: row.spot.coordinate, style: style, proxy: proxy)
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
            .equatable()
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
        guard request.id != appliedRequest, AppLaunch.mapCamera == nil else { return }
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

/// The hint shown while Adjust Location is on. Done and Cancel are the window toolbar's.
struct AdjustLocationBanner: View {
    var body: some View {
        HStack(spacing: IterSpace.sm) {
            Image(systemName: "scope").foregroundStyle(IterColor.accent)
            Text("Move the map to put the crosshair on your spot", comment: "Hint banner while Adjust Location is on")
                .font(IterFont.subheadline)
        }
        .padding(.horizontal, IterSpace.md)
        .padding(.vertical, IterSpace.sm)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .combine)
    }
}

/// The hint shown while Add Spot mode is on.
struct AddSpotBanner: View {
    var onCancel: () -> Void

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
        .glassEffect(.regular, in: .capsule)
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
