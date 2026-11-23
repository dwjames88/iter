import Foundation
import MapKit
import IterModel
import IterGoActivity

/// The part of the map the user can see, in points: the whole view and what covers its edges (the Dynamic Island and status bar
/// on top, the sheet's current detent below, the sheet's column or controls at the sides).
struct GoMapViewport: Equatable, Sendable {
    var size: CGSize
    var top: Double = 0
    var leading: Double = 0
    var bottom: Double = 0
    var trailing: Double = 0

    var visibleWidth: Double { max(1, size.width - leading - trailing) }
    var visibleHeight: Double { max(1, size.height - top - bottom) }
}

/// Where the Go map looks, worked out without a map (BLUEPRINT §10.8, GLASS-RULES). Pure: the same inputs always give the same
/// rectangle, so it is unit-tested instead of eyeballed.
///
/// The camera holds you and the stop you are heading to, then today's remaining stops in order for as long as the picture is
/// still legible (`legibleVisibleMeters`). It never frames the whole trip: a trip that spans a continent would put every pin on
/// top of the next one. The points sit inside the uncovered part of the screen with `pinPadding` all round, so no pin sits under
/// the sheet, the Dynamic Island or the screen edge.
enum GoMapCamera {
    /// Space kept between a framed point and the edge of the uncovered area: the selected pin's radius, plus air.
    static let pinPadding: Double = 36
    /// The uncovered area is never narrower than this on the ground, so standing at the stop does not zoom to a doorstep.
    static let minimumVisibleMeters: Double = 1_500
    /// Past this much ground across the screen, today's extra stops stay off the picture: you and the next stop come first.
    static let legibleVisibleMeters: Double = 120_000

    struct Framing {
        /// The rectangle the whole view shows, with the framed points inside the uncovered part.
        var rect: MKMapRect
        /// Which of the offered stops are inside it (the next stop, then today's in order).
        var framedStops: [Coordinate]
        var includesUser: Bool
        /// Map points per screen point at this framing (what `GoMapPins.groups` needs).
        var mapPointsPerPoint: Double
    }

    /// - `user`: where you are, if known. `next`: the stop you are heading to (or the one you are at).
    /// - `today`: the stops of that day still to do, in order (it may include `next`).
    static func frame(user: Coordinate?, next: Coordinate?, today: [Coordinate], viewport: GoMapViewport) -> Framing? {
        let visW = max(viewport.visibleWidth - 2 * pinPadding, 1)
        let visH = max(viewport.visibleHeight - 2 * pinPadding, 1)
        guard viewport.size.width > 0, viewport.size.height > 0 else { return nil }

        var points: [Coordinate] = []
        var includesUser = false
        if let user { points.append(user); includesUser = true }
        if let next { points.append(next) }
        var framed: [Coordinate] = next.map { [$0] } ?? []
        let rest = today.filter { $0 != next }
        if points.isEmpty {
            // Nothing to anchor on: take the first stop and let the rest in while they fit.
            guard let first = rest.first else { return nil }
            points = [first]
            framed = [first]
        }

        func scale(_ points: [Coordinate]) -> Double {
            let box = bounds(points)
            let latitude = points[0].latitude
            let floor = minimumVisibleMeters * MKMapPointsPerMeterAtLatitude(latitude) / visW
            return max(box.size.width / visW, box.size.height / visH, floor)
        }
        func legible(_ s: Double) -> Bool {
            s * viewport.size.width / MKMapPointsPerMeterAtLatitude(points[0].latitude) <= legibleVisibleMeters
        }

        for stop in rest where !framed.contains(stop) {
            let trial = points + [stop]
            guard legible(scale(trial)) else { break }
            points = trial
            framed.append(stop)
        }

        let box = bounds(points)
        let s = scale(points)
        // The uncovered area's centre, in screen points, must land on the box's centre on the ground.
        let centreX = viewport.leading + viewport.visibleWidth / 2
        let centreY = viewport.top + viewport.visibleHeight / 2
        let rect = MKMapRect(x: box.midX - centreX * s, y: box.midY - centreY * s,
                             width: viewport.size.width * s, height: viewport.size.height * s)
        return Framing(rect: rect, framedStops: framed, includesUser: includesUser, mapPointsPerPoint: s)
    }

    /// Where a coordinate lands on screen (points from the view's top left) when the map shows `rect` in `viewport`.
    static func screenPoint(_ coordinate: Coordinate, rect: MKMapRect, viewport: GoMapViewport) -> CGPoint {
        let p = MKMapPoint(CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude))
        return CGPoint(x: (p.x - rect.minX) / rect.width * viewport.size.width, y: (p.y - rect.minY) / rect.height * viewport.size.height)
    }

    private static func bounds(_ coordinates: [Coordinate]) -> MKMapRect {
        var rect = MKMapRect.null
        for c in coordinates {
            let p = MKMapPoint(CLLocationCoordinate2D(latitude: c.latitude, longitude: c.longitude))
            rect = rect.union(MKMapRect(origin: p, size: MKMapSize(width: 0, height: 0)))
        }
        return rect
    }
}

/// One thing drawn for stops: a numbered plate, or a badge standing for several stops too close to tell apart at this zoom.
struct GoMapPinGroup: Equatable, Identifiable {
    var stops: [GoStopInfo]
    var coordinate: Coordinate
    var containsNext: Bool

    var id: UUID { stops[0].id }
    var isCluster: Bool { stops.count > 1 }

    /// "4" for one stop, "6–8" for a cluster.
    var label: String {
        let numbers = stops.map(\.number)
        guard let lo = numbers.min(), let hi = numbers.max(), lo != hi else { return "\(numbers.first ?? 0)" }
        return "\(lo)–\(hi)"
    }

    /// "Stops 6, 7 and 8".
    var accessibilityLabel: String {
        let numbers = stops.map(\.number).sorted().map(String.init)
        guard numbers.count > 1 else { return "Stop \(numbers.first ?? "")" }
        return "Stops " + numbers.dropLast().joined(separator: ", ") + " and " + numbers[numbers.count - 1]
    }
}

/// Keeps pins from stacking: stops whose plates would overlap on screen at the current zoom merge into one badge.
enum GoMapPins {
    /// Plates closer than this (points, centre to centre) merge. A pin is 28 pt across (36 when selected); a little air on top.
    static let minimumSeparation: Double = 32

    /// `mapPointsPerPoint`: how much ground one screen point covers right now. Merging is transitive (a chain of near stops is one
    /// badge) and sits at the middle of its members. Order follows the stops' order.
    static func groups(stops: [GoStopInfo], nextID: UUID?, mapPointsPerPoint: Double,
                       minimumSeparation: Double = GoMapPins.minimumSeparation) -> [GoMapPinGroup] {
        guard mapPointsPerPoint > 0 else { return stops.map { GoMapPinGroup(stops: [$0], coordinate: $0.coordinate, containsNext: $0.id == nextID) } }
        let points = stops.map { MKMapPoint(CLLocationCoordinate2D(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)) }
        let limit = minimumSeparation * mapPointsPerPoint
        // Union-find over "closer than a plate".
        var parent = Array(stops.indices)
        func root(_ i: Int) -> Int {
            var i = i
            while parent[i] != i { parent[i] = parent[parent[i]]; i = parent[i] }
            return i
        }
        for i in stops.indices {
            for j in stops.indices where j > i {
                let dx = points[i].x - points[j].x, dy = points[i].y - points[j].y
                if (dx * dx + dy * dy).squareRoot() < limit { parent[root(j)] = root(i) }
            }
        }
        var order: [Int] = []
        var members: [Int: [Int]] = [:]
        for i in stops.indices {
            let r = root(i)
            if members[r] == nil { order.append(r) }
            members[r, default: []].append(i)
        }
        return order.map { r in
            let ids = members[r] ?? []
            let infos = ids.map { stops[$0] }
            let mx = ids.map { points[$0].x }.reduce(0, +) / Double(ids.count)
            let my = ids.map { points[$0].y }.reduce(0, +) / Double(ids.count)
            let c = MKMapPoint(x: mx, y: my).coordinate
            let centre = ids.count == 1 ? infos[0].coordinate : Coordinate(latitude: c.latitude, longitude: c.longitude)
            return GoMapPinGroup(stops: infos, coordinate: centre, containsNext: infos.contains { $0.id == nextID })
        }
    }
}
