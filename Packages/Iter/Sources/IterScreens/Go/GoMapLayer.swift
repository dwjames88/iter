import SwiftUI
import MapKit
import IterModel
import IterGoActivity
import IterUI

/// The map under the sheet: your position, the stops still to do as solid numbered plates, the route in the route colour.
/// Apple Maps geometry in the standard style; "Dark for Night Shooting" mutes it. The camera fits you and the stops.
public struct GoMapLayer: View {
    let snapshot: GoSnapshot
    let routePath: [Coordinate]
    @AppStorage(GoNightView.key) private var night = false
    @State private var position: MapCameraPosition = .automatic

    public init(snapshot: GoSnapshot, routePath: [Coordinate]) {
        self.snapshot = snapshot
        self.routePath = routePath
    }

    public var body: some View {
        let stops = Self.stops(snapshot)
        let nextID = (snapshot.next ?? stops.first)?.id
        Map(position: $position) {
            UserAnnotation()
            if routePath.count > 1 {
                MapPolyline(coordinates: routePath.map(Self.clCoordinate))
                    .stroke(IterColor.route, lineWidth: IterStroke.route)
            }
            ForEach(stops) { stop in
                Annotation(stop.name, coordinate: Self.clCoordinate(stop.coordinate), anchor: .center) {
                    GoMapPlate(number: stop.number, isNext: stop.id == nextID)
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(emphasis: night ? .muted : .automatic))
        .onAppear { fit() }
        .onChange(of: Self.fitKey(snapshot)) { _, _ in fit() }
    }

    // MARK: Pure helpers

    /// The stops to pin: the remaining schedule, else the next stop, else the one you are at.
    static func stops(_ snapshot: GoSnapshot) -> [GoStopInfo] {
        if let schedule = snapshot.schedule, !schedule.isEmpty { return schedule.map(\.stop) }
        if let next = snapshot.next { return [next] }
        return snapshot.current.map { [$0] } ?? []
    }

    /// Everything the camera should hold: you, then the stops.
    static func fitCoordinates(_ snapshot: GoSnapshot) -> [Coordinate] {
        (snapshot.here.map { [$0] } ?? []) + stops(snapshot).map(\.coordinate)
    }

    static func fitKey(_ snapshot: GoSnapshot) -> [Coordinate] { fitCoordinates(snapshot) }

    static func clCoordinate(_ c: Coordinate) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: c.latitude, longitude: c.longitude)
    }

    /// A map rect around the points. On iPhone the sheet covers the lower half, so the rect grows downward and the points
    /// sit in the top half; a single point gets a small neighbourhood.
    static func fitRect(_ coordinates: [Coordinate], sheetCoversBottom: Bool) -> MKMapRect? {
        guard !coordinates.isEmpty else { return nil }
        var rect = MKMapRect.null
        for c in coordinates {
            let p = MKMapPoint(clCoordinate(c))
            rect = rect.union(MKMapRect(origin: p, size: MKMapSize(width: 0, height: 0)))
        }
        let minSpan = MKMapPointsPerMeterAtLatitude(coordinates[0].latitude) * 6_000
        var w = max(rect.size.width * 1.4, minSpan)
        var h = max(rect.size.height * 1.4, minSpan)
        let cx = rect.midX, cy = rect.midY
        if sheetCoversBottom {
            h *= 2.1
            w = max(w, h * 0.46)
            return MKMapRect(x: cx - w / 2, y: rect.minY - (h - rect.size.height) * 0.18, width: w, height: h)
        }
        w = max(w, h * 0.6)
        h = max(h, w * 0.6)
        return MKMapRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h)
    }

    private func fit() {
        #if os(iOS)
        let covered = true
        #else
        let covered = false
        #endif
        if let rect = Self.fitRect(Self.fitCoordinates(snapshot), sheetCoversBottom: covered) {
            position = .rect(rect)
        }
    }
}

/// A stop's pin: a solid numbered plate (map pins are never material). The stop you are heading to is larger and coral.
struct GoMapPlate: View {
    let number: Int
    let isNext: Bool

    var body: some View {
        Text(number, format: .number)
            .font(IterFont.headline)
            .monospacedDigit()
            .foregroundStyle(IterColor.onAccent)
            .frame(width: isNext ? IterSize.mapPinSelected : IterSize.mapPin, height: isNext ? IterSize.mapPinSelected : IterSize.mapPin)
            .background(isNext ? IterColor.mapPin : IterColor.mapPinInactive, in: Circle())
            .overlay { Circle().strokeBorder(IterColor.backgroundContent, lineWidth: IterStroke.regular) }
            .accessibilityLabel("Stop \(number)")
    }
}
