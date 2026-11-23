import SwiftUI
import MapKit
import IterFeatures
import IterModel
import IterUI

/// How the `Preferences.mapStyle` raw value ("hybrid" default, "standard", "imagery") maps onto MapKit.
enum BuildMapStyle {
    static func make(_ raw: String) -> MapStyle {
        switch raw {
        case "standard": .standard(elevation: .realistic)
        case "imagery": .imagery(elevation: .realistic)
        default: .hybrid(elevation: .realistic)
        }
    }
}

/// The camera maths of the route map, pure so it can be tested.
enum RouteCamera {
    /// A region that fits the trip, never wider than a 40 degree span.
    static func region(_ fit: GeoRegion) -> MKCoordinateRegion {
        MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: fit.center.latitude, longitude: fit.center.longitude),
                           span: MKCoordinateSpan(latitudeDelta: min(fit.latitudeDelta, 40), longitudeDelta: min(fit.longitudeDelta, 40)))
    }

    /// Whether `point` is inside the middle 80 percent of `region` (a selected stop outside it is panned to).
    static func comfortablyVisible(_ point: Coordinate, in region: MKCoordinateRegion) -> Bool {
        abs(point.latitude - region.center.latitude) <= region.span.latitudeDelta * 0.4
            && abs(point.longitude - region.center.longitude) <= region.span.longitudeDelta * 0.4
    }
}

/// The route map with numbered waypoints for a trip: solid number plates (lodging and waypoints with their glyph, the selected
/// one scaled), a polyline per drive (other days dimmed while a day is selected, estimates dashed), your location, and a camera
/// that fits the trip first and then follows the selected day or stop with the zoom kept. Nothing here is material.
public struct TripRouteMap: View {
    let model: BuildModel
    let mapStyle: String
    @State private var position: MapCameraPosition = .automatic
    @State private var visible: MKCoordinateRegion?
    @State private var fitted = false

    /// - Parameter mapStyle: `Preferences.mapStyle`.
    public init(model: BuildModel, mapStyle: String = "hybrid") {
        self.model = model
        self.mapStyle = mapStyle
    }

    public var body: some View {
        let content = model.mapContent
        let selectedDay = model.selectedDay
        Map(position: $position, interactionModes: [.pan, .zoom, .rotate]) {
            UserAnnotation()
            ForEach(content.legs) { leg in
                MapPolyline(coordinates: leg.path.map(Self.location))
                    .stroke(selectedDay == nil || selectedDay == leg.day ? IterColor.route : IterColor.routeInactive,
                            style: StrokeStyle(lineWidth: IterStroke.route, lineCap: .round, lineJoin: .round,
                                               dash: leg.isEstimate ? [IterStroke.dashLength, IterStroke.dashGap] : []))
            }
            if let start = content.startCoordinate {
                Annotation("", coordinate: Self.location(start), anchor: .center) {
                    Image(systemName: "house.fill").font(.system(size: 11, weight: .semibold)).foregroundStyle(IterColor.textPrimary)
                        .frame(width: 24, height: 24).background(IterColor.backgroundContent, in: Circle())
                        .accessibilityLabel(Text("Start place", comment: "Map pin label"))
                }
            }
            ForEach(content.waypoints) { waypoint in
                Annotation(waypoint.name, coordinate: Self.location(waypoint.coordinate), anchor: .center) {
                    WaypointPlate(waypoint: waypoint, model: model)
                        .onTapGesture { model.selectStop(waypoint.stopID) }
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(BuildMapStyle.make(mapStyle))
        .onMapCameraChange(frequency: .onEnd) { context in visible = context.region }
        .onAppear { fitIfNeeded() }
        .onChange(of: model.cameraRegion) { refit() }
        .onChange(of: model.selectedStopID) { follow() }
    }

    static func location(_ c: Coordinate) -> CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: c.latitude, longitude: c.longitude) }

    // MARK: Camera

    private func fitIfNeeded() {
        guard !fitted, let fit = model.cameraRegion else { return }
        fitted = true
        position = .region(RouteCamera.region(fit))
    }

    /// The trip or the selected day changed: refit while the map is untouched; once the user has moved it, only pan.
    private func refit() {
        guard let fit = model.cameraRegion else { return }
        if !fitted { fitIfNeeded(); return }
        if position.positionedByUser, let visible {
            let target = RouteCamera.region(fit)
            guard !RouteCamera.comfortablyVisible(Coordinate(latitude: target.center.latitude, longitude: target.center.longitude), in: visible) else { return }
            withAnimation { position = .region(MKCoordinateRegion(center: target.center, span: visible.span)) }
        } else {
            withAnimation { position = .region(RouteCamera.region(fit)) }
        }
    }

    /// A stop was chosen: pan to it only when its pin is out of the comfortable middle; the zoom is kept.
    private func follow() {
        guard let id = model.selectedStopID, let waypoint = model.mapContent.waypoints.first(where: { $0.stopID == id }),
              let visible, !RouteCamera.comfortablyVisible(waypoint.coordinate, in: visible) else { return }
        withAnimation { position = .region(MKCoordinateRegion(center: Self.location(waypoint.coordinate), span: visible.span)) }
    }
}

/// A numbered waypoint: a solid disc with the trip-wide number (a glyph for lodging and waypoints), scaled when selected.
struct WaypointPlate: View {
    let waypoint: BuildWaypoint
    let model: BuildModel

    var body: some View {
        let selected = model.selectedStopID == waypoint.stopID
        let dimmed = model.selectedDay != nil && model.selectedDay != waypoint.day
        Group {
            switch waypoint.kind {
            case .light:
                Text(waypoint.number, format: .number).font(.system(size: 13, weight: .semibold)).monospacedDigit()
            case .lodging:
                Image(systemName: "bed.double.fill").font(.system(size: 11, weight: .semibold))
            case .waypoint:
                Image(systemName: "mappin").font(.system(size: 11, weight: .semibold))
            }
        }
        .foregroundStyle(IterColor.onAccent)
        .frame(width: 26, height: 26)
        .background(dimmed ? IterColor.mapPinInactive : IterColor.mapPin, in: Circle())
        .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
        .shadow(radius: selected ? IterEvent.pinShadowRadiusSelected : IterEvent.pinShadowRadius, y: 1)
        .scaleEffect(selected ? IterEvent.pinScaleSelected : 1)
        .animation(.spring, value: selected)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Stop \(waypoint.number), \(waypoint.name)", comment: "VoiceOver: a map pin"))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}
