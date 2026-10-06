import SwiftUI
import MapKit
import AppKit
import IterCore
import IterData
import IterDesign
import IterFeatures

/// The map: pins with hierarchy, one selection shared with the list, the place card, and Add Spot mode.
struct ExploreMapPane: View {
    @Bindable var explore: ExploreModel
    @Environment(\.renderMode) private var renderMode
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
        .onGeometryChange(for: CGSize.self) { $0.size } action: { paneSize = $0 }
        .overlay(alignment: .bottomTrailing) {
            if let row = explore.selectedRow, !explore.isAddingSpot {
                ExplorePlaceCard(row: row, day: explore.day, size: cardSize) { explore.select(nil, from: .map) }
                    .padding(IterSpace.md)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.smooth, value: explore.selectedID)
    }

    /// The card's width is its token, shrunk to fit a narrow pane. Its height is at most half the pane (less the
    /// padding), so the selected pin, which the camera centres, stays visible above it.
    private var cardSize: CGSize {
        guard paneSize != .zero else { return CGSize(width: IterSize.placeCardWidth, height: IterSize.placeCardMaxHeight) }
        let inset = IterSpace.md * 2
        let width = min(IterSize.placeCardWidth, max(0, paneSize.width - inset))
        let height = min(IterSize.placeCardMaxHeight, max(0, (paneSize.height - inset) * 0.5))
        return CGSize(width: width, height: height)
    }

    // MARK: Live map

    private var mapSelection: Binding<String?> {
        Binding(get: { explore.selectedID },
                set: { if !explore.isAddingSpot { explore.select($0, from: .map) } })
    }

    private var liveMap: some View {
        MapReader { proxy in
            Map(position: $position, selection: mapSelection) {
                // MapKit has no z-index: later annotations draw on top, so the selected pin goes last.
                ForEach(explore.pins.sorted { zOrder($0.style) < zOrder($1.style) }) { pin in
                    pinAnnotation(pin)
                }
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
                MapZoomStepper()
                MapCompass()
                MapScaleView()
            }
            .onMapCameraChange(frequency: .onEnd) { context in
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
            if let request { apply(request, animated: true) }
        }
        .onAppear {
            if let request = explore.cameraRequest { apply(request, animated: false) }
        }
    }

    private func pinAnnotation(_ pin: ExplorePin) -> some MapContent {
        let anchor: UnitPoint = pin.style == .selected ? .bottom : .center
        return Annotation(pin.row.spot.name, coordinate: clCoordinate(pin.row.spot.coordinate), anchor: anchor) {
            pinBody(pin)
        }
        .tag(pin.id)
        .annotationTitles(.hidden)
    }

    private func pinBody(_ pin: ExplorePin) -> some View {
        ExplorePinView(pin: pin)
            .allowsHitTesting(!explore.isAddingSpot)
            .onHover { inside in
                if inside { explore.hoveredID = pin.id } else if explore.hoveredID == pin.id { explore.hoveredID = nil }
            }
            .contextMenu { ExploreSpotMenu(spot: pin.row.spot, day: explore.day) }
    }

    private func zOrder(_ style: ExplorePinStyle) -> Int {
        switch style {
        case .selected: 2
        case .chip: 1
        case .dot: 0
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

    var body: some View {
        GeometryReader { geo in
            let region = MapCameraPolicy.fit(explore.fitCoordinates)
            ZStack(alignment: .topLeading) {
                Rectangle().fill(IterColor.backgroundControl)
                if let region {
                    ForEach(explore.pins.sorted { z($0) < z($1) }) { pin in
                        ExplorePinView(pin: pin)
                            .position(project(pin.row.spot.coordinate, region, geo.size))
                    }
                    if let draft = explore.draftCoordinate {
                        Image(systemName: "mappin.circle.fill").font(.title).foregroundStyle(IterColor.mapPin)
                            .position(project(draft, region, geo.size))
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

    private func z(_ pin: ExplorePin) -> Int { pin.style == .selected ? 2 : pin.style == .chip ? 1 : 0 }

    private func project(_ c: Coordinate, _ r: GeoRegion, _ size: CGSize) -> CGPoint {
        let x = (c.longitude - (r.center.longitude - r.longitudeDelta / 2)) / r.longitudeDelta
        let y = ((r.center.latitude + r.latitudeDelta / 2) - c.latitude) / r.latitudeDelta
        return CGPoint(x: x * size.width, y: y * size.height)
    }
}
