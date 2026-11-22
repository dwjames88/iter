import Foundation
import IterModel
import IterSources

/// A `LiveLocation` for tests: records what it was asked and plays back whatever the test sends.
@MainActor
public final class ScriptedLocation: LiveLocation {
    public struct AppliedMode: Hashable, Sendable {
        public var mode: LocationMode
        public var at: Date
    }

    public private(set) var authorization: LocationAuthorization
    /// Every `apply`, in order, including repeats.
    public private(set) var applied: [AppliedMode] = []
    /// Every request made, in order (`.whenInUse` or `.always`).
    public private(set) var authorizationRequests: [LocationAuthorization] = []
    /// When set, a request moves `authorization` to this (at most to what was asked for) and emits the change.
    public var grantOnRequest: Bool = false

    public let events: AsyncStream<LocationEvent>
    private let continuation: AsyncStream<LocationEvent>.Continuation
    private let clock: any SourceClock

    public init(clock: any SourceClock, authorization: LocationAuthorization = .notDetermined) {
        self.clock = clock
        self.authorization = authorization
        (events, continuation) = AsyncStream.makeStream(of: LocationEvent.self, bufferingPolicy: .unbounded)
    }

    public var currentMode: LocationMode? { applied.last?.mode }

    public func requestWhenInUse() {
        authorizationRequests.append(.whenInUse)
        if grantOnRequest, authorization == .notDetermined { setAuthorization(.whenInUse) }
    }

    public func requestAlways() {
        authorizationRequests.append(.always)
        if grantOnRequest, authorization == .notDetermined || authorization == .whenInUse { setAuthorization(.always) }
    }

    public func apply(_ mode: LocationMode) {
        applied.append(AppliedMode(mode: mode, at: clock.now))
    }

    /// Pushes an event to the consumer.
    public func send(_ event: LocationEvent) { continuation.yield(event) }

    public func sendAll(_ fixes: [LocationFix]) { for fix in fixes { send(.fix(fix)) } }

    /// Changes authorization and emits `.authorizationChanged`.
    public func setAuthorization(_ value: LocationAuthorization) {
        authorization = value
        send(.authorizationChanged(value))
    }

    public func finish() { continuation.finish() }
}

/// Builds timestamped fixes along a polyline at a given speed and fix interval. Deterministic: the same inputs and
/// seed give the same fixes.
public enum LocationTrace {
    /// A small deterministic generator (a 64-bit LCG). Not for anything but test noise.
    public struct SeededGenerator: RandomNumberGenerator, Sendable {
        private var state: UInt64
        public init(seed: UInt64) { state = seed &* 6364136223846793005 &+ 1442695040888963407 }
        public mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state
        }
    }

    public static func length(of path: [Coordinate]) -> Double {
        zip(path, path.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) }
    }

    /// The point `distanceM` along the path (clamped to its ends) and the course of the segment there.
    public static func point(along path: [Coordinate], at distanceM: Double) -> (coordinate: Coordinate, course: Double)? {
        guard let first = path.first else { return nil }
        guard path.count > 1 else { return (first, 0) }
        var remaining = max(0, distanceM)
        for (a, b) in zip(path, path.dropFirst()) {
            let segment = a.distance(to: b)
            if remaining <= segment || (b == path.last && segment == 0) {
                let f = segment > 0 ? remaining / segment : 0
                return (Coordinate(latitude: a.latitude + (b.latitude - a.latitude) * f,
                                   longitude: a.longitude + (b.longitude - a.longitude) * f), a.bearing(to: b))
            }
            remaining -= segment
        }
        let n = path.count
        return (path[n - 1], path[n - 2].bearing(to: path[n - 1]))
    }

    /// Fixes every `interval` seconds from `start`, travelling the whole polyline at `speedMs`, plus a final fix at
    /// the end. `jitterM` adds up to that many metres of seeded noise to each axis (accuracy is reported as
    /// `max(accuracyM, jitterM)`). Course is the segment bearing.
    public static func fixes(along path: [Coordinate], speedMs: Double, interval: TimeInterval = 1, start: Date,
                             accuracyM: Double = 5, jitterM: Double = 0, seed: UInt64 = 1) -> [LocationFix] {
        guard path.count > 0, speedMs > 0, interval > 0 else { return [] }
        let total = length(of: path)
        let duration = total / speedMs
        var rng = SeededGenerator(seed: seed)
        var out: [LocationFix] = []
        var t: TimeInterval = 0
        while true {
            let atEnd = t >= duration
            let d = atEnd ? total : speedMs * t
            if let p = point(along: path, at: d) {
                out.append(fix(at: p.coordinate, course: p.course, speed: speedMs, time: start.addingTimeInterval(t),
                               accuracyM: accuracyM, jitterM: jitterM, rng: &rng))
            }
            if atEnd { break }
            t += interval
        }
        return out
    }

    /// Fixes while parked: `speed` 0, at `coordinate`, every `interval` seconds for `duration`.
    public static func stationary(at coordinate: Coordinate, duration: TimeInterval, interval: TimeInterval = 10, start: Date,
                                  accuracyM: Double = 5, jitterM: Double = 0, seed: UInt64 = 1) -> [LocationFix] {
        guard interval > 0 else { return [] }
        var rng = SeededGenerator(seed: seed)
        var out: [LocationFix] = []
        var t: TimeInterval = 0
        while t <= duration {
            out.append(fix(at: coordinate, course: nil, speed: 0, time: start.addingTimeInterval(t),
                           accuracyM: accuracyM, jitterM: jitterM, rng: &rng))
            t += interval
        }
        return out
    }

    private static func fix(at c: Coordinate, course: Double?, speed: Double, time: Date, accuracyM: Double, jitterM: Double,
                            rng: inout SeededGenerator) -> LocationFix {
        var coordinate = c
        if jitterM > 0 {
            let dn = Double.random(in: -jitterM...jitterM, using: &rng)
            let de = Double.random(in: -jitterM...jitterM, using: &rng)
            let mPerDeg = Coordinate.earthRadiusMeters * .pi / 180
            coordinate = Coordinate(latitude: c.latitude + dn / mPerDeg,
                                    longitude: c.longitude + de / (mPerDeg * max(0.01, cos(c.latitude * .pi / 180))))
        }
        return LocationFix(coordinate: coordinate, accuracyM: max(accuracyM, jitterM), speedMs: speed, courseDeg: course, timestamp: time)
    }
}
