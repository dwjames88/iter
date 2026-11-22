import Foundation
import CoreGraphics
import IterCore

/// Maps sky positions onto a top-down compass rose: the observer at the centre, the horizon on the rim, the zenith at
/// the centre (radius falls linearly with altitude), azimuth clockwise with `rotation` drawn at the top.
public struct RoseProjection: Sendable, Equatable {
    public var center: CGPoint
    /// The horizon ring.
    public var radius: CGFloat
    /// The azimuth drawn straight up: 0 = north up; the classic-view bearing when "view up".
    public var rotation: Double

    public init(center: CGPoint, radius: CGFloat, rotation: Double = 0) {
        self.center = center
        self.radius = radius
        self.rotation = rotation
    }

    /// The point for a sky position. Altitude is clamped to 0...90 (below the horizon sits on the rim).
    public func point(azimuth: Double, altitude: Double) -> CGPoint {
        let a = min(max(altitude, 0), 90)
        return point(azimuth: azimuth, radius: radius * CGFloat((90 - a) / 90))
    }

    /// The point at radius `r` from the centre for an azimuth; screen y grows downward (SwiftUI).
    public func point(azimuth: Double, radius r: CGFloat) -> CGPoint {
        let theta = (azimuth - rotation) * .pi / 180
        return CGPoint(x: center.x + r * CGFloat(sin(theta)), y: center.y - r * CGFloat(cos(theta)))
    }

    /// The sky position under a point (altitude may be negative outside the rim).
    public func position(at p: CGPoint) -> SkyPosition {
        let dx = Double(p.x - center.x)
        let dy = Double(center.y - p.y)
        let r = (dx * dx + dy * dy).squareRoot()
        let theta = r == 0 ? 0 : atan2(dx, dy) * 180 / .pi
        var az = (theta + rotation).truncatingRemainder(dividingBy: 360)
        if az < 0 { az += 360 }
        let alt = radius == 0 ? 0 : 90 - 90 * r / Double(radius)
        return SkyPosition(altitude: alt, azimuth: az)
    }
}

/// One day's sun and moon on a top-down compass rose: the arcs above the horizon, the day's events, the facing wedge
/// and the one strong fact about sunrise or sunset. Pure geometry; the views draw it.
public struct SkyRose: Sendable {
    /// A sky position at an instant.
    public struct Sample: Sendable, Equatable {
        public var date: Date
        public var position: SkyPosition
        public init(date: Date, position: SkyPosition) {
            self.date = date
            self.position = position
        }
    }

    /// Which body a path belongs to.
    public enum Body: String, Sendable { case sun, moon }

    /// The events the rose marks.
    public enum EventKind: String, Sendable, CaseIterable { case sunrise, solarNoon, sunset, moonrise, moonset }

    /// An event with where its body is at that instant.
    public struct Event: Sendable, Equatable {
        public var kind: EventKind
        public var date: Date
        public var position: SkyPosition
        public var body: Body
        public init(kind: EventKind, date: Date, position: SkyPosition, body: Body) {
            self.kind = kind
            self.date = date
            self.position = position
            self.body = body
        }
    }

    public var dayStart: Date
    public var dayEnd: Date
    /// The whole day's samples, as given.
    public var sun: [Sample]
    public var moon: [Sample]
    /// Runs of the path above the horizon, in time order, each starting and ending with a point interpolated (linearly
    /// in time and in azimuth, handling the 360/0 wrap) at altitude 0 where the path crosses the horizon.
    /// Below-horizon parts are not included.
    public var sunArcs: [[Sample]]
    public var moonArcs: [[Sample]]
    /// Sunrise, solar noon, sunset, moonrise and moonset that fall inside the day. Solar noon is included only when
    /// the sun is above the horizon then.
    public var events: [Event]
    public var facing: Double?
    public var sunKind: SunEvents.DayKind
    /// The moon's phase at the day's solar noon.
    public var moonPhase: MoonPhase
    /// Solar noon, which splits "about sunrise" from "about sunset".
    public var solarNoon: Date

    private let ephemeris: any Ephemeris

    /// Half-width of the classic view's wedge, degrees (the same 35° the old "in your frame" sentence used).
    public static let viewHalfWidth: Double = 35

    /// Builds the rose from a day's samples and events; positions of the events come from the ephemeris.
    public static func make(sun: [Sample], moon: [Sample], sunEvents: SunEvents, moonEvents: MoonEvents, facing: Double?,
                            ephemeris: any Ephemeris, coordinate: Coordinate, dayStart: Date, dayEnd: Date) -> SkyRose {
        var events: [Event] = []
        func add(_ kind: EventKind, _ date: Date?, _ body: Body) {
            guard let date, date >= dayStart, date <= dayEnd else { return }
            let position = body == .sun ? ephemeris.sunPosition(at: date, coordinate: coordinate)
                                        : ephemeris.moonPosition(at: date, coordinate: coordinate)
            if kind == .solarNoon && position.altitude <= 0 { return }
            events.append(Event(kind: kind, date: date, position: position, body: body))
        }
        add(.sunrise, sunEvents.sunrise, .sun)
        add(.solarNoon, sunEvents.solarNoon, .sun)
        add(.sunset, sunEvents.sunset, .sun)
        add(.moonrise, moonEvents.rise, .moon)
        add(.moonset, moonEvents.set, .moon)
        return SkyRose(dayStart: dayStart, dayEnd: dayEnd, sun: sun, moon: moon,
                       sunArcs: arcs(of: sun), moonArcs: arcs(of: moon), events: events, facing: facing,
                       sunKind: sunEvents.kind, moonPhase: ephemeris.moonPhase(at: sunEvents.solarNoon),
                       solarNoon: sunEvents.solarNoon, ephemeris: ephemeris)
    }

    /// The moon's phase at any instant, for the readout.
    public func phase(at date: Date) -> MoonPhase { ephemeris.moonPhase(at: date) }

    /// The event of a kind, if it falls inside the day.
    public func event(_ kind: EventKind) -> Event? { events.first { $0.kind == kind } }

    /// Smallest angle between two bearings, 0...180.
    public static func angularDifference(_ a: Double, _ b: Double) -> Double {
        var d = (a - b).truncatingRemainder(dividingBy: 360)
        if d < 0 { d += 360 }
        return d > 180 ? 360 - d : d
    }

    // MARK: Arcs

    /// Splits samples into runs above the horizon, closing each at an interpolated altitude-0 crossing.
    static func arcs(of samples: [Sample]) -> [[Sample]] {
        var out: [[Sample]] = []
        var run: [Sample] = []
        for i in samples.indices {
            let b = samples[i]
            let up = b.position.altitude > 0
            if i == 0 {
                if up { run = [b] }
                continue
            }
            let a = samples[i - 1]
            let wasUp = a.position.altitude > 0
            if !wasUp && up {
                run = [crossing(a, b), b]
            } else if wasUp && up {
                run.append(b)
            } else if wasUp && !up {
                run.append(crossing(a, b))
                out.append(run)
                run = []
            }
        }
        if !run.isEmpty { out.append(run) }
        return out
    }

    /// The point between two samples where altitude is 0.
    private static func crossing(_ a: Sample, _ b: Sample) -> Sample {
        let da = a.position.altitude, db = b.position.altitude
        let f = da == db ? 0 : min(max(da / (da - db), 0), 1)
        let date = a.date.addingTimeInterval(b.date.timeIntervalSince(a.date) * f)
        var delta = (b.position.azimuth - a.position.azimuth).truncatingRemainder(dividingBy: 360)
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        var az = (a.position.azimuth + delta * f).truncatingRemainder(dividingBy: 360)
        if az < 0 { az += 360 }
        return Sample(date: date, position: SkyPosition(altitude: 0, azimuth: az))
    }

    // MARK: Fact

    /// The one strong fact: about sunrise when `time` is before solar noon, else about sunset.
    public enum Fact: Sendable, Equatable {
        /// The event's azimuth is within the view wedge of facing.
        case inside(Event)
        /// Degrees beyond the wedge's edge (difference minus the half-width), above zero.
        case outside(Event, by: Double)
        /// No facing known.
        case noView(Event)
        /// Polar night or polar day (or the event falls outside the day).
        case noSunrise, noSunset
    }

    /// The fact about sunrise (before solar noon) or sunset (after it) against the way the spot faces.
    public func fact(at time: Date) -> Fact {
        let morning = time < solarNoon
        guard let event = event(morning ? .sunrise : .sunset) else { return morning ? .noSunrise : .noSunset }
        guard let facing else { return .noView(event) }
        let diff = Self.angularDifference(event.position.azimuth, facing)
        return diff <= Self.viewHalfWidth ? .inside(event) : .outside(event, by: diff - Self.viewHalfWidth)
    }

    // MARK: Hit testing

    /// For dragging on the rose: the time on whichever path (sun arcs, then moon arcs) passes nearest `point`, within
    /// `maxDistance` points, interpolated along the nearest segment so it is minute-accurate. The sun wins when both
    /// are in range and it is no more than 4 pt further than the moon. Nil when nothing is near.
    public func nearestTime(to point: CGPoint, projection: RoseProjection, maxDistance: CGFloat) -> (body: Body, date: Date)? {
        let s = Self.nearest(in: sunArcs, to: point, projection: projection)
        let m = Self.nearest(in: moonArcs, to: point, projection: projection)
        let sunHit = s.flatMap { $0.distance <= maxDistance ? $0 : nil }
        let moonHit = m.flatMap { $0.distance <= maxDistance ? $0 : nil }
        switch (sunHit, moonHit) {
        case let (s?, m?): return s.distance <= m.distance + 4 ? (.sun, s.date) : (.moon, m.date)
        case let (s?, nil): return (.sun, s.date)
        case let (nil, m?): return (.moon, m.date)
        default: return nil
        }
    }

    private static func nearest(in arcs: [[Sample]], to p: CGPoint, projection: RoseProjection) -> (distance: CGFloat, date: Date)? {
        var best: (distance: CGFloat, date: Date)?
        func consider(_ d: CGFloat, _ date: Date) {
            if best == nil || d < best!.distance { best = (d, date) }
        }
        for arc in arcs {
            let pts = arc.map { projection.point(azimuth: $0.position.azimuth, altitude: $0.position.altitude) }
            if arc.count == 1 { consider(hypot(pts[0].x - p.x, pts[0].y - p.y), arc[0].date) }
            guard arc.count >= 2 else { continue }
            for i in 1..<arc.count {
                let a = pts[i - 1], b = pts[i]
                let vx = b.x - a.x, vy = b.y - a.y
                let len2 = vx * vx + vy * vy
                let t = len2 == 0 ? 0 : min(max(((p.x - a.x) * vx + (p.y - a.y) * vy) / len2, 0), 1)
                let cx = a.x + vx * t, cy = a.y + vy * t
                let date = arc[i - 1].date.addingTimeInterval(arc[i].date.timeIntervalSince(arc[i - 1].date) * Double(t))
                consider(hypot(cx - p.x, cy - p.y), date)
            }
        }
        return best
    }
}
