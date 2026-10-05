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
    @State private var position: MapCameraPosition = .automatic
    @State private var appliedRequest = 0

    var body: some View {
        ZStack {
            if renderMode == .snapshot {
                ExploreMapStandIn(explore: explore)
            } else {
                liveMap
            }
        }
        .overlay(alignment: .top) {
            if explore.isAddingSpot {
                AddSpotBanner { explore.isAddingSpot = false }
                    .padding(IterSpace.md)
            }
        }
        .overlay(alignment: .bottom) {
            if let row = explore.selectedRow, !explore.isAddingSpot {
                ExplorePlaceCard(row: row, day: explore.day) { explore.select(nil, from: .map) }
                    .padding(IterSpace.md)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.smooth, value: explore.selectedID)
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
                explore.cameraDidChange(to: GeoRegion(center: Coordinate(latitude: r.center.latitude, longitude: r.center.longitude),
                                                      latitudeDelta: r.span.latitudeDelta, longitudeDelta: r.span.longitudeDelta))
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
        let region: MKCoordinateRegion
        switch request.kind {
        case .fit(let r):
            region = MKCoordinateRegion(center: clCoordinate(r.center),
                                        span: MKCoordinateSpan(latitudeDelta: min(r.latitudeDelta, 120), longitudeDelta: min(r.longitudeDelta, 300)))
        case .center(let c):
            // Keep the zoom the user chose; only move.
            let span = explore.visibleRegion.map { MKCoordinateSpan(latitudeDelta: $0.latitudeDelta, longitudeDelta: $0.longitudeDelta) }
                ?? MKCoordinateSpan(latitudeDelta: 2, longitudeDelta: 2)
            region = MKCoordinateRegion(center: clCoordinate(c), span: span)
        }
        if animated {
            withAnimation(.smooth) { position = .region(region) }
        } else {
            position = .region(region)
        }
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
            let coordinates = explore.rows.map(\.spot.coordinate)
            let region = GeoRegion.enclosing(coordinates, padding: 0.25, minimumDelta: 0.1)
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
