import SwiftUI
import MapKit
import IterCore
import IterDesign
import IterFeatures

/// The Locations map: a marker per listed spot, framed to fit them, selection shared with the list.
/// Snapshot renders draw `MapStandIn` instead (a live map does not render offscreen).
struct LocationsMap: View {
    let items: [SavedItem]
    @Binding var selection: Set<UUID>
    /// What covers the map: the toolbar above it and the panel floating over its leading edge.
    var insets = EdgeInsets()
    @Namespace private var mapScope
    @Environment(\.renderMode) private var renderMode
    @Environment(AppModel.self) private var model
    @State private var position: MapCameraPosition
    @State private var paneSize = CGSize.zero
    /// The camera as last settled, so a selection knows whether the map is already closer in than the selection radius.
    @State private var visible: GeoRegion?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(MapStyleChoice.storageKey) private var mapStyleRaw = MapStyleChoice.default.rawValue
    @State private var daylight = DaylightClock()
    @AppStorage(DaylightClock.storageKey) private var showsDaylight = true
    /// Moving your own spots: built on first use (it needs the app model from the environment).
    @State private var dragHolder = OwnPinDragHolder()
    @State private var proxyBox = MapProxyBox()
    /// A press that starts a drag selects its pin; the camera must stay still under the pointer, so that one selection is not framed.
    @State private var quietSelection: UUID?

    init(items: [SavedItem], selection: Binding<Set<UUID>>, insets: EdgeInsets = EdgeInsets()) {
        self.items = items
        _selection = selection
        self.insets = insets
        // Start framed, so MapKit never shows its automatic world camera first. `-IterMapCamera` (tests, screenshots) wins.
        if let launch = AppLaunch.mapCamera {
            _position = State(initialValue: .camera(MapCamera(
                centerCoordinate: CLLocationCoordinate2D(latitude: launch.coordinate.latitude, longitude: launch.coordinate.longitude),
                distance: launch.distanceMetres, heading: 0, pitch: launch.pitch)))
        } else {
            _position = State(initialValue: Self.framing(items))
        }
    }

    var body: some View {
        ZStack {
            if renderMode == .snapshot {
                MapStandIn(pins: drawOrder.map { item in
                    let event = model.savedEvent(for: item.spot)
                    return .init(id: item.id.uuidString, coordinate: item.spot.coordinate, label: item.spot.name,
                                 selected: selection.contains(item.id),
                                 event: event.map { .init(window: $0.window, zone: item.spot.timeZone, isLoading: $0.isLoading, isTomorrow: $0.isTomorrow) })
                })
            } else if paneSize.width > 0, paneSize.height > 0 {
                liveMap
            } else {
                Color.clear
            }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
            // Only the first size matters (it creates the map); later ones are not state, so a live resize does not re-run this view.
            if paneSize == .zero { paneSize = size }
        }
        .onChange(of: items.map(\.id)) { if AppLaunch.mapCamera == nil { withAnimation { position = Self.framing(items) } } }
    }

    /// The model that moves your own spots, with the map's selection hooked to it.
    private var drag: OwnPinDragModel {
        let made = dragHolder.model(for: model)
        made.onBegin = { id in
            guard let uuid = UUID(uuidString: id), selection != [uuid] else { return }
            quietSelection = uuid
            selection = [uuid]
        }
        return made
    }

    /// Where the pin's drawn tip is: the event unit and the selected name stand on their tip, the plain marker is centred.
    private func anchor(event: SavedEvent?, selected: Bool) -> UnitPoint {
        UnitPoint(x: MapPinAnchor.horizontal, y: MapPinAnchor.vertical(for: event != nil || selected ? .selected : .dot))
    }

    private var liveMap: some View {
        MapReader { proxy in
            let _ = proxyBox.proxy = proxy
            map(proxy)
        }
    }

    private func map(_ proxy: MapProxy) -> some View {
        let drag = drag
        return Map(position: $position, bounds: .globe, selection: mapSelection, scope: mapScope) {
            if daylight.isShown(isOn: showsDaylight, style: MapStyleChoice(stored: mapStyleRaw)) { DaylightOverlay(daylight.shading) }
            ForEach(drawOrder) { item in
                let selected = selection.contains(item.id)
                let id = item.id.uuidString
                let event = model.savedEvent(for: item.spot)
                let movable = drag.canMove(id)
                let at = drag.displayCoordinate(for: id, stored: item.spot.coordinate)
                // The exact point of a spot of yours that is selected or carried: the pin's pointer ends here.
                if movable, selected || drag.dragging?.id == id {
                    Annotation("", coordinate: clCoordinate(at), anchor: .center) { PinTipDot() }
                        .annotationTitles(.hidden)
                }
                Annotation(item.spot.name, coordinate: clCoordinate(at), anchor: anchor(event: event, selected: selected)) {
                    LocationsPinView(spot: item.spot, event: event, isSelected: selected)
                        .ownPinDrag(id: id, stored: item.spot.coordinate, host: drag, proxy: proxy, isEnabled: movable) { drop in
                            probeDrop(drop, proxy: proxy)
                        }
                }
                .tag(item.id)
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(MapStyleChoice(stored: mapStyleRaw).mapStyle())
        .daylightClock(daylight)
        .mapControls { MapScaleView() }
        .safeAreaPadding(insets)
        .overlay(alignment: .topTrailing) {
            MapControlStack(scope: mapScope).padding(.top, insets.top)
        }
        .mapScope(mapScope)
        .onMapCameraChange(frequency: .onEnd) { context in
            let r = context.region
            visible = GeoRegion(center: Coordinate(latitude: r.center.latitude, longitude: r.center.longitude),
                                latitudeDelta: r.span.latitudeDelta, longitudeDelta: r.span.longitudeDelta)
            if PinDragProbe.shared.isOn { PinDragProbe.shared.cameraSettled(context.camera); probeSpot(proxy) }
        }
        .onMapCameraChange(frequency: .continuous) { context in
            if PinDragProbe.shared.isOn {
                let c = context.camera
                PinDragProbe.shared.event(String(format: "camera %.6f,%.6f pitch %.1f dist %.1f", c.centerCoordinate.latitude, c.centerCoordinate.longitude, c.pitch, c.distance))
            }
        }
        // Selecting one spot (a row or a pin) frames the selection radius around it, or only pans when already closer.
        // A pin picked up to be moved is selected without it, and `-IterMapCamera` keeps the camera it was given.
        .onChange(of: selection) { _, new in
            if PinDragProbe.shared.isOn {
                PinDragProbe.shared.note("selectedID", new.count == 1 ? new.first!.uuidString : "")
                PinDragProbe.shared.event("selected \(new.count == 1 ? new.first!.uuidString : "-")")
                Task { try? await Task.sleep(for: .milliseconds(600)); probeSpot(proxy) }
            }
            let quiet = quietSelection
            quietSelection = nil
            guard new.count == 1, new.first != quiet, AppLaunch.mapCamera == nil,
                  let item = items.first(where: { $0.id == new.first }) else { return }
            let target = MapCameraPolicy.selectionRegion(current: visible, spot: item.spot.coordinate)
            let region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: target.center.latitude, longitude: target.center.longitude),
                span: MKCoordinateSpan(latitudeDelta: min(target.latitudeDelta, 120), longitudeDelta: min(target.longitudeDelta, 300)))
            if reduceMotion { position = .region(region) } else { withAnimation(.smooth) { position = .region(region) } }
        }
    }

    // MARK: Probe (`-IterPinDragProbe`, see PinDragProbe)

    /// Reports the selected spot of yours (or the last one reported) with where its pin is drawn.
    private func probeSpot(_ proxy: MapProxy) {
        let chosen = selection.count == 1 ? selection.first.map(\.uuidString) : nil
        guard let id = chosen.flatMap({ drag.canMove($0) ? $0 : nil }) ?? PinDragProbe.shared.lastID,
              let uuid = UUID(uuidString: id), let place = model.store.place(id: uuid) else { return }
        // From the store, not `items`: a delayed report runs in a copy of this view made before the drop.
        let style = selection.contains(uuid) ? "selected" : (model.savedEvent(for: place.spot) != nil ? "chip" : "dot")
        PinDragProbe.shared.spotShown(id: id, coordinate: place.coordinate, style: style, proxy: proxy)
    }

    private func probeDrop(_ drop: PinDrop, proxy: MapProxy) {
        guard PinDragProbe.shared.isOn, let uuid = UUID(uuidString: drop.id), let stored = model.store.place(id: uuid)?.coordinate else { return }
        PinDragProbe.shared.moveCommitted(stored: stored, expected: drop.expected, delta: drop.delta, tipBefore: drop.tipBefore, proxy: proxy)
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            PinDragProbe.shared.tipAfterDrop(stored: stored, proxy: proxy)
            probeSpot(proxy)
        }
    }

    private func clCoordinate(_ c: Coordinate) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: c.latitude, longitude: c.longitude)
    }

    /// The selected pins last, so they draw on top.
    private var drawOrder: [SavedItem] {
        items.filter { !selection.contains($0.id) } + items.filter { selection.contains($0.id) }
    }

    /// One marker selected on the map selects its row; a click on empty map clears the selection. A click on the selected
    /// spot of yours keeps it selected (it is the first half of "click it, then drag it").
    private var mapSelection: Binding<UUID?> {
        Binding(get: { selection.count == 1 ? selection.first : nil },
                set: { new in
                    if let selected = selection.count == 1 ? selection.first : nil,
                       let item = items.first(where: { $0.id == selected }),
                       proxyBox.keepsSelection(writing: new?.uuidString, selectedID: selected.uuidString,
                                               selectedCoordinate: item.spot.coordinate,
                                               selectedIsMovable: drag.canMove(selected.uuidString)) { return }
                    selection = new.map { [$0] } ?? []
                })
    }

    private static func framing(_ items: [SavedItem]) -> MapCameraPosition {
        guard let r = GeoRegion.enclosing(items.map(\.spot.coordinate), padding: 0.4, minimumDelta: 0.2) else { return .automatic }
        return .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: r.center.latitude, longitude: r.center.longitude),
            span: MKCoordinateSpan(latitudeDelta: r.latitudeDelta, longitudeDelta: r.longitudeDelta)))
    }
}

/// One Locations map pin: the event unit exactly as Explore draws it (`EventScore` pin variant, borderless, selection
/// by scale and shadow), showing the spot's next sunrise or sunset, the same window as its list row.
private struct LocationsPinView: View {
    let spot: Spot
    let event: SavedEvent?
    let isSelected: Bool


    var body: some View {
        Group {
            if let event {
                EventScore(window: event.window, zone: spot.timeZone, timeStyle: .start, variant: .pin,
                           isLoading: event.isLoading, isTomorrow: event.isTomorrow, isSelected: isSelected)
            } else if isSelected {
                Text(spot.name)
                    .font(IterFont.captionStrong)
                    .foregroundStyle(IterColor.textPrimary)
                    .lineLimit(1)
                    .padding(.vertical, IterSpace.xs)
                    .padding(.horizontal, IterSpace.sm)
                    .background(IterColor.backgroundContent, in: Capsule())
                    .shadow(radius: IterEvent.pinShadowRadiusSelected, y: 1)
                    .scaleEffect(IterEvent.pinScaleSelected, anchor: .bottom)
            } else {
                Circle().fill(IterColor.backgroundControl)
                    .frame(width: IterSpace.sm + IterSpace.xs, height: IterSpace.sm + IterSpace.xs)
                    .overlay(Circle().strokeBorder(IterColor.separator, lineWidth: IterStroke.hairline))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(spot.name))
        .accessibilityValue(event.map { Text(LightText.accessibilityDescription($0.window)) } ?? Text(verbatim: ""))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

}
