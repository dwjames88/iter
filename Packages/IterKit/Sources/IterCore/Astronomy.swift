import Foundation

/// A body's apparent position: altitude above the horizon and compass azimuth, both in degrees.
/// Azimuth is measured clockwise from true north (0 = N, 90 = E). Altitude includes atmospheric refraction.
public struct SkyPosition: Codable, Hashable, Sendable {
    public var altitude: Double
    public var azimuth: Double

    public init(altitude: Double, azimuth: Double) {
        self.altitude = altitude
        self.azimuth = azimuth
    }
}

/// What the sun does on one local day at one place. Any event can be nil near the poles.
public struct SunEvents: Codable, Hashable, Sendable {
    public enum DayKind: String, Codable, Hashable, Sendable {
        case normal
        /// The sun never sets (midnight sun).
        case polarDay
        /// The sun never rises.
        case polarNight
    }

    public var day: LocalDay
    public var kind: DayKind
    public var solarNoon: Date
    public var astronomicalDawn: Date?   // −18°
    public var nauticalDawn: Date?       // −12°
    public var civilDawn: Date?          // −6°
    public var sunrise: Date?            // −0.833° (upper limb, standard refraction)
    public var goldenMorningEnd: Date?   // +6° rising
    public var goldenEveningStart: Date? // +6° setting
    public var sunset: Date?
    public var civilDusk: Date?
    public var nauticalDusk: Date?
    public var astronomicalDusk: Date?

    public init(day: LocalDay, kind: DayKind, solarNoon: Date,
                astronomicalDawn: Date? = nil, nauticalDawn: Date? = nil, civilDawn: Date? = nil,
                sunrise: Date? = nil, goldenMorningEnd: Date? = nil, goldenEveningStart: Date? = nil,
                sunset: Date? = nil, civilDusk: Date? = nil, nauticalDusk: Date? = nil, astronomicalDusk: Date? = nil) {
        self.day = day
        self.kind = kind
        self.solarNoon = solarNoon
        self.astronomicalDawn = astronomicalDawn
        self.nauticalDawn = nauticalDawn
        self.civilDawn = civilDawn
        self.sunrise = sunrise
        self.goldenMorningEnd = goldenMorningEnd
        self.goldenEveningStart = goldenEveningStart
        self.sunset = sunset
        self.civilDusk = civilDusk
        self.nauticalDusk = nauticalDusk
        self.astronomicalDusk = astronomicalDusk
    }
}

/// The moon's phase at an instant.
public struct MoonPhase: Codable, Hashable, Sendable {
    /// Illuminated fraction of the disc, 0 (new) to 1 (full).
    public var illumination: Double
    /// Phase angle as a cycle fraction: 0 new, 0.25 first quarter, 0.5 full, 0.75 last quarter.
    public var cycle: Double
    public var isWaxing: Bool { cycle < 0.5 }

    public init(illumination: Double, cycle: Double) {
        self.illumination = illumination
        self.cycle = cycle
    }

    public enum Name: String, Codable, CaseIterable, Sendable {
        case new, waxingCrescent, firstQuarter, waxingGibbous, full, waningGibbous, lastQuarter, waningCrescent
    }

    public var name: Name {
        let index = Int((cycle * 8).rounded()) % 8
        return Name.allCases[index]
    }
}

/// Moonrise and moonset during one local day (either may be absent).
public struct MoonEvents: Codable, Hashable, Sendable {
    public var day: LocalDay
    public var rise: Date?
    public var set: Date?
    public var alwaysUp: Bool
    public var alwaysDown: Bool

    public init(day: LocalDay, rise: Date?, set: Date?, alwaysUp: Bool = false, alwaysDown: Bool = false) {
        self.day = day
        self.rise = rise
        self.set = set
        self.alwaysUp = alwaysUp
        self.alwaysDown = alwaysDown
    }
}

/// Sun and moon calculations. Implemented in IterAstro; injected so the light engine can be tested with fixed events.
public protocol Ephemeris: Sendable {
    func sunEvents(on day: LocalDay, at coordinate: Coordinate, in timeZone: TimeZone) -> SunEvents
    func sunPosition(at date: Date, coordinate: Coordinate) -> SkyPosition
    func moonPosition(at date: Date, coordinate: Coordinate) -> SkyPosition
    func moonPhase(at date: Date) -> MoonPhase
    func moonEvents(on day: LocalDay, at coordinate: Coordinate, in timeZone: TimeZone) -> MoonEvents
}

extension Ephemeris {
    /// Positions sampled across a local day, for drawing the sun and moon arcs.
    public func path(of body: CelestialBody, on day: LocalDay, at coordinate: Coordinate, in timeZone: TimeZone,
                     everyMinutes step: Int = 10) -> [(date: Date, position: SkyPosition)] {
        let start = day.start(in: timeZone)
        let end = day.adding(days: 1).start(in: timeZone)
        var out: [(Date, SkyPosition)] = []
        var t = start
        while t <= end {
            out.append((t, body == .sun ? sunPosition(at: t, coordinate: coordinate) : moonPosition(at: t, coordinate: coordinate)))
            t = t.addingTimeInterval(TimeInterval(step * 60))
        }
        return out
    }
}

public enum CelestialBody: String, Codable, Sendable {
    case sun, moon
}
