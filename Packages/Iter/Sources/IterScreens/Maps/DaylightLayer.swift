import SwiftUI
import MapKit
import IterAstro
import IterModel
import IterUI

/// The pure geometry behind the day/night layer: the night side of the globe at an instant, cut at the antimeridian, and the
/// rule for when a map is zoomed out far enough to show it. No SwiftUI here, so it is unit-tested directly.
public struct DaylightGeometry: Equatable, Sendable {
    /// The night side, one or two closed rings (longitude -180...180, latitude within +-89.5).
    public var night: [[Coordinate]]
    /// The day/night line (sun at the horizon), one open path per ring, without the pole or antimeridian closing edges.
    public var terminator: [[Coordinate]]
    /// The sub-solar point, where the Sun is overhead.
    public var subsolar: Coordinate

    public init(date: Date, step: Double = 2) {
        subsolar = Daylight.subsolarPoint(at: date)
        night = Daylight.nightPolygons(at: date, step: step)
        terminator = night.map(Self.openLine)
    }

    /// The map shows daylight only when it is zoomed out: the visible span is at least this many degrees of latitude.
    public static let minimumLatitudeSpan: Double = 20

    /// True when a map whose visible region spans `latitudeSpan` degrees of latitude should draw the layer.
    public static func isVisible(latitudeSpan: Double) -> Bool { latitudeSpan >= minimumLatitudeSpan }

    /// Drops the edges that run along a pole (|lat| >= 89.5) or down a cut meridian (lon = +-180): they close the polygon but
    /// are not the day/night line.
    static func openLine(_ ring: [Coordinate]) -> [Coordinate] {
        func isClosingEdge(_ a: Coordinate, _ b: Coordinate) -> Bool {
            (abs(a.latitude) >= 89.49 && abs(b.latitude) >= 89.49) || (abs(a.longitude) == 180 && a.longitude == b.longitude)
        }
        guard ring.count > 2 else { return ring }
        // Rotate so the path starts right after a closing edge, then take points until the next one.
        var start = 0
        for i in 0..<ring.count where isClosingEdge(ring[i], ring[(i + 1) % ring.count]) { start = (i + 1) % ring.count }
        var line: [Coordinate] = []
        for k in 0..<ring.count {
            let i = (start + k) % ring.count
            let next = ring[(i + 1) % ring.count]
            if abs(ring[i].latitude) >= 89.49 && abs(next.latitude) >= 89.49 { continue }
            if abs(ring[i].longitude) == 180 && ring[i].longitude == next.longitude { continue }
            line.append(ring[i])
        }
        return line
    }
}

/// The night side of the globe as a soft shade, with the day/night line, for a `Map`'s content builder:
///
///     Map { ... ; if showDaylight && DaylightGeometry.isVisible(latitudeSpan: span) { DaylightTerminator(date: now) } }
///
/// Zoomed in it would be a flat wash with no edge in view, so maps add it only when zoomed out (see `isVisible`).
public struct DaylightTerminator: MapContent {
    let geometry: DaylightGeometry

    public init(date: Date) { geometry = DaylightGeometry(date: date) }

    public var body: some MapContent {
        ForEach(Array(geometry.night.enumerated()), id: \.offset) { _, ring in
            MapPolygon(coordinates: ring.map(Self.location))
                .foregroundStyle(IterColor.skyNight.opacity(0.38))
        }
        ForEach(Array(geometry.terminator.enumerated()), id: \.offset) { _, line in
            MapPolyline(coordinates: line.map(Self.location))
                .stroke(IterColor.skyNight.opacity(0.65), lineWidth: 1.5)
        }
    }

    private static func location(_ c: Coordinate) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: c.latitude, longitude: c.longitude)
    }
}
