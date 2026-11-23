import SwiftUI
import MapKit
import IterFeatures
import IterModel
import IterUI

extension EnvironmentValues {
    /// `Preferences.mapStyle` ("hybrid" default, "standard", "imagery"). The shell sets it from the preferences it owns.
    @Entry public var findMapStyle: String = "hybrid"
}

/// Waits for a burst of changes to end before running the work (map size changes reach the model once, after a resize stops).
@MainActor
final class FindDebouncer {
    private var task: Task<Void, Never>?
    func schedule(after delay: Duration = .milliseconds(150), _ work: @escaping @MainActor () -> Void) {
        task?.cancel()
        task = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            work()
        }
    }
}

enum FindMapGeometry {
    static func cl(_ c: Coordinate) -> CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: c.latitude, longitude: c.longitude) }
    static func coordinate(_ c: CLLocationCoordinate2D) -> Coordinate { Coordinate(latitude: c.latitude, longitude: c.longitude) }
    static func region(_ r: GeoRegion) -> MKCoordinateRegion {
        MKCoordinateRegion(center: cl(r.center), span: MKCoordinateSpan(latitudeDelta: max(r.latitudeDelta, 0.001), longitudeDelta: max(r.longitudeDelta, 0.001)))
    }
    static func geoRegion(_ r: MKCoordinateRegion) -> GeoRegion {
        GeoRegion(center: coordinate(r.center), latitudeDelta: r.span.latitudeDelta, longitudeDelta: r.span.longitudeDelta)
    }
    /// The four corners of a box, for an area with no real outline.
    static func box(_ r: GeoRegion) -> [Coordinate] {
        let (lat, lon) = (r.latitudeDelta / 2, r.longitudeDelta / 2)
        return [Coordinate(latitude: r.center.latitude + lat, longitude: r.center.longitude - lon),
                Coordinate(latitude: r.center.latitude + lat, longitude: r.center.longitude + lon),
                Coordinate(latitude: r.center.latitude - lat, longitude: r.center.longitude + lon),
                Coordinate(latitude: r.center.latitude - lat, longitude: r.center.longitude - lon)]
    }
    /// True when `c` is inside `region` shrunk by `margin` (a fraction of the span) on every side.
    static func contains(_ region: GeoRegion, _ c: Coordinate, margin: Double = 0.1) -> Bool {
        abs(c.latitude - region.center.latitude) <= region.latitudeDelta * (0.5 - margin)
            && abs(c.longitude - region.center.longitude) <= region.longitudeDelta * (0.5 - margin)
    }
    static func style(_ name: String) -> MapStyle {
        switch name {
        case "standard": .standard(elevation: .realistic)
        case "imagery": .imagery(elevation: .realistic)
        default: .hybrid(elevation: .realistic)
        }
    }
}

/// The Find map: full bleed, the user's location, result pins and clusters from the model's precomputed content, your own spots
/// (draggable, never clustered), the resolved area's outline, Add Spot and Adjust Location. Draws nothing new in its body:
/// every list comes from `model.mapContent`.
struct FindMapView: View {
    @Bindable var model: FindModel
    @Binding var visibleRegion: GeoRegion?
    /// What covers the map: the floating card on the leading edge.
    var insets = EdgeInsets()
    @Environment(\.findMapStyle) private var styleName
    @Namespace private var mapScope
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var width: CGFloat = 0
    @State private var resize = FindDebouncer()
    @State private var rings: [[CLLocationCoordinate2D]] = []

    private var spots: OwnSpotEditor { model.spots }
    private var adjustingID: String? { spots.adjusting.map { "place:\($0.placeID.uuidString)" } }

    var body: some View {
        MapReader { proxy in
            Map(position: $position, selection: selection, scope: mapScope) {
                UserAnnotation()
                ForEach(rings.indices, id: \.self) { i in
                    MapPolygon(coordinates: rings[i])
                        .foregroundStyle(IterColor.accent.opacity(0.08))
                        .stroke(IterColor.accent, lineWidth: 2)
                }
                ForEach(model.mapContent.clusters) { cluster in
                    Annotation("", coordinate: FindMapGeometry.cl(cluster.coordinate), anchor: .center) {
                        FindClusterView(cluster: cluster)
                    }
                    .tag(cluster.id)
                    .annotationTitles(.hidden)
                }
                ForEach(model.mapContent.pins) { pin in
                    if pin.id != adjustingID { pinAnnotation(pin, proxy: proxy) }
                }
            }
            .mapStyle(FindMapGeometry.style(styleName))
            .mapControls { MapScaleView() }
            .safeAreaPadding(insets)
            .overlay(alignment: .topTrailing) { controls }
            .overlay { if spots.adjusting != nil { crosshair } }
            .overlay(alignment: .top) { banner }
            .mapScope(mapScope)
            .onMapCameraChange(frequency: .onEnd) { context in
                let region = FindMapGeometry.geoRegion(context.region)
                visibleRegion = region
                if width > 0 { model.setViewport(region: region, width: width) }
            }
            .onMapCameraChange(frequency: .continuous) { context in
                guard spots.adjusting != nil else { return }
                spots.adjustCenterChanged(FindMapGeometry.coordinate(context.camera.centerCoordinate))
            }
            .simultaneousGesture(SpatialTapGesture(coordinateSpace: .global).onEnded { tap in
                guard spots.isAdding, let c = proxy.convert(tap.location, from: .global) else { return }
                let at = FindMapGeometry.coordinate(c)
                Task { _ = await model.dropPin(at: at) }
            })
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { new in
            let first = width == 0
            width = new
            if first { return }
            resize.schedule { if let r = visibleRegion { model.setViewport(region: r, width: new) } }
        }
        .onChange(of: model.mapContent.outline, initial: true) { _, _ in rebuildRings() }
        .onChange(of: model.mapContent.areaRegion) { _, new in
            guard let new else { return }
            withAnimation { position = .region(FindMapGeometry.region(new)) }
        }
        .onChange(of: model.selectedID) { _, _ in panToSelection() }
        .onChange(of: spots.adjusting?.placeID) { _, id in
            guard id != nil, let session = spots.adjusting else { return }
            let span = visibleRegion.map { ($0.latitudeDelta, $0.longitudeDelta) } ?? (0.02, 0.02)
            position = .region(FindMapGeometry.region(GeoRegion(center: session.original, latitudeDelta: span.0, longitudeDelta: span.1)))
        }
        .onExitCommand { cancelModes() }
    }

    // MARK: Selection and camera

    private var selection: Binding<String?> {
        Binding(get: { model.selectedID }, set: { new in
            guard !spots.isAdding, spots.adjusting == nil else { return }
            if let new, new.hasPrefix("cluster/") {
                if let cluster = model.mapContent.clusters.first(where: { $0.id == new }),
                   let region = FindClusterZoom.region(for: cluster, rows: model.rows) {
                    withAnimation { position = .region(FindMapGeometry.region(region)) }
                }
                return
            }
            model.select(new)
        })
    }

    /// Pans only when the selected place is out of view; never zooms out.
    private func panToSelection() {
        guard let card = model.card, let visible = visibleRegion, !FindMapGeometry.contains(visible, card.coordinate) else { return }
        withAnimation {
            position = .region(FindMapGeometry.region(GeoRegion(center: card.coordinate, latitudeDelta: visible.latitudeDelta, longitudeDelta: visible.longitudeDelta)))
        }
    }

    private func rebuildRings() {
        let content = model.mapContent
        if !content.outline.isEmpty {
            rings = content.outline.map { $0.map(FindMapGeometry.cl) }
        } else if let box = content.areaRegion {
            rings = [FindMapGeometry.box(box).map(FindMapGeometry.cl)]
        } else {
            rings = []
        }
    }

    private func cancelModes() {
        if spots.isAdding { spots.cancelAdding() }
        if spots.adjusting != nil { spots.finishAdjusting(commit: false) }
    }

    // MARK: Pins

    @MapContentBuilder
    private func pinAnnotation(_ pin: FindPin, proxy: MapProxy) -> some MapContent {
        let selected = model.selectedID == pin.id
        if pin.isMovable, let id = FindCardText.placeID(from: pin.id) {
            Annotation(pin.title, coordinate: FindMapGeometry.cl(spots.displayCoordinate(for: id, stored: pin.coordinate)),
                       anchor: FindPinView.anchor(for: pin)) {
                FindPinView(pin: pin, isSelected: selected)
                    .equatable()
                    .modifier(FindOwnPinDrag(placeID: id, stored: pin.coordinate, model: model, proxy: proxy))
            }
            .tag(pin.id)
            .annotationTitles(.hidden)
        } else {
            Annotation(pin.title, coordinate: FindMapGeometry.cl(pin.coordinate), anchor: FindPinView.anchor(for: pin, isSelected: selected)) {
                FindPinView(pin: pin, isSelected: selected).equatable()
            }
            .tag(pin.id)
            .annotationTitles(.hidden)
        }
    }

    // MARK: Overlays

    private var controls: some View {
        MapControlStack(actions: {
            MapControlButton(title: "Add Spot", systemImage: "mappin.and.ellipse",
                             help: "Add your own spot: click the map to drop a pin (Esc to cancel)", isOn: spots.isAdding) {
                if spots.isAdding { spots.cancelAdding() } else { spots.beginAdding() }
            }
        }, controls: { EmptyView() }, accessories: {
            VStack(spacing: MapControlStack<EmptyView, EmptyView, EmptyView>.gap) {
                MapUserLocationButton(scope: mapScope)
                MapCompass(scope: mapScope)
                #if os(macOS)
                MapZoomStepper(scope: mapScope)
                #endif
            }
        })
        .padding(.top, insets.top)
    }

    private var crosshair: some View {
        Image(systemName: "plus")
            .font(.system(size: 32, weight: .light))
            .foregroundStyle(IterColor.mapPin)
            .shadow(radius: 1)
            .padding(insets)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    @ViewBuilder private var banner: some View {
        if spots.adjusting != nil {
            FindModeBanner(text: "Move the map to put the crosshair on your spot", primary: ("Done", {
                let id = spots.adjusting?.placeID
                spots.finishAdjusting(commit: true)
                if let id { model.didMoveSpot(id) }
            }), secondary: ("Cancel", { spots.finishAdjusting(commit: false) }))
                .padding(.top, IterSpace.md)
                .padding(.leading, insets.leading)
        } else if spots.isAdding {
            FindModeBanner(text: "Click the map to drop a pin", primary: nil, secondary: ("Cancel", { spots.cancelAdding() }))
                .padding(.top, IterSpace.md)
                .padding(.leading, insets.leading)
        }
    }
}

/// The banner over the map in Add Spot and Adjust Location: a glass capsule (controls layer) with Cancel (Esc) and, for
/// Adjust Location, Done.
struct FindModeBanner: View {
    let text: String
    let primary: (String, () -> Void)?
    let secondary: (String, () -> Void)

    var body: some View {
        GlassEffectContainer {
            HStack(spacing: IterSpace.md) {
                Text(verbatim: text).font(IterFont.bodyEmphasis)
                Button(secondary.0, action: secondary.1)
                    .keyboardShortcut(.cancelAction)
                    .help("Cancel (Esc)")
                if let primary {
                    Button(primary.0, action: primary.1)
                        .buttonStyle(.borderedProminent)
                        .tint(IterColor.accent)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.horizontal, IterSpace.lg)
            .padding(.vertical, IterSpace.sm)
            .glassEffect(.regular, in: .capsule)
        }
    }
}

/// Lets you move one of your own spots: the pointer drags the pin, the pin's tip follows the pointer at the grab offset, and
/// the drop stores exactly the coordinate under the tip (one "Move Spot"; nothing is stored unless the pin moved).
struct FindOwnPinDrag: ViewModifier {
    let placeID: UUID
    let stored: Coordinate
    let model: FindModel
    let proxy: MapProxy
    @State private var grab: CGSize?
    @State private var tipAtStart: CGPoint?

    func body(content: Content) -> some View {
        content
            #if os(macOS)
            .pointerStyle(model.spots.dragging?.id == placeID ? .grabActive : .grabIdle)
            #endif
            .offset(y: model.spots.dragging?.id == placeID ? -5 : 0)
            .gesture(drag)
            .help("Drag to move your spot")
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .global)
            .onChanged { value in
                if model.spots.dragging == nil {
                    guard model.spots.beginDrag(placeID) else { return }
                    grab = nil
                    tipAtStart = proxy.convert(FindMapGeometry.cl(stored), to: .global)
                }
                if grab == nil {
                    let tip = tipAtStart ?? value.startLocation
                    grab = CGSize(width: value.startLocation.x - tip.x, height: value.startLocation.y - tip.y)
                }
                let g = grab ?? .zero
                let point = CGPoint(x: value.location.x - g.width, y: value.location.y - g.height)
                if let c = proxy.convert(point, from: .global) { model.spots.drag(to: FindMapGeometry.coordinate(c)) }
            }
            .onEnded { _ in
                guard model.spots.dragging != nil else { return }
                let moved = model.spots.dragging.map { $0.coordinate != stored } ?? false
                model.spots.endDrag(commit: moved)
                grab = nil
                tipAtStart = nil
                if moved { model.didMoveSpot(placeID) }
            }
    }
}
