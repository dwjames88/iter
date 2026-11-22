import Foundation

/// A drive between two points. `isEstimate` is true when no road route was available and the time is a straight-line guess.
public struct Leg: Codable, Hashable, Sendable {
    public var from: Coordinate
    public var to: Coordinate
    public var seconds: TimeInterval
    public var meters: Double
    public var isEstimate: Bool
    /// The road geometry for drawing, if known.
    public var path: [Coordinate]

    public init(from: Coordinate, to: Coordinate, seconds: TimeInterval, meters: Double, isEstimate: Bool, path: [Coordinate] = []) {
        self.from = from
        self.to = to
        self.seconds = seconds
        self.meters = meters
        self.isEstimate = isEstimate
        self.path = path
    }

    /// Straight-line distance × 1.3 at 70 km/h: an honest, labelled fallback.
    public static func estimate(from a: Coordinate, to b: Coordinate) -> Leg {
        let meters = a.distance(to: b) * 1.3
        return Leg(from: a, to: b, seconds: meters / (70_000.0 / 3600.0), meters: meters, isEstimate: true, path: [a, b])
    }
}

/// A route over one or more legs, with the traffic context it was computed in. Kept small; Phase 2 may extend it.
public struct Route: Codable, Hashable, Sendable {
    public var path: [Coordinate]
    public var seconds: TimeInterval
    public var meters: Double
    /// The departure time the estimate was computed for; nil = no particular time.
    public var departing: Date?
    public var isTrafficAware: Bool
    public var isEstimate: Bool

    public init(path: [Coordinate] = [], seconds: TimeInterval, meters: Double, departing: Date? = nil,
                isTrafficAware: Bool = false, isEstimate: Bool = false) {
        self.path = path
        self.seconds = seconds
        self.meters = meters
        self.departing = departing
        self.isTrafficAware = isTrafficAware
        self.isEstimate = isEstimate
    }

    public init(leg: Leg, departing: Date? = nil, isTrafficAware: Bool = false) {
        self.init(path: leg.path, seconds: leg.seconds, meters: leg.meters, departing: departing,
                  isTrafficAware: isTrafficAware, isEstimate: leg.isEstimate)
    }

    /// Joins legs end to end; an estimate anywhere makes the whole route an estimate.
    public init(legs: [Leg], departing: Date? = nil, isTrafficAware: Bool = false) {
        self.init(path: legs.flatMap(\.path), seconds: legs.reduce(0) { $0 + $1.seconds }, meters: legs.reduce(0) { $0 + $1.meters },
                  departing: departing, isTrafficAware: isTrafficAware, isEstimate: legs.contains { $0.isEstimate })
    }
}

/// An estimated time of arrival: how long the drive takes and the resulting instant.
public struct ETA: Codable, Hashable, Sendable {
    public var seconds: TimeInterval
    public var arrival: Date
    public var departing: Date

    public init(seconds: TimeInterval, arrival: Date, departing: Date) {
        self.seconds = seconds
        self.arrival = arrival
        self.departing = departing
    }
}
