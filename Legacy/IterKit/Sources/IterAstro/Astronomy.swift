import Foundation
import IterCore

/// Sun and Moon calculations with our own low-precision series (Meeus, Astronomical Algorithms).
///
/// Accuracy: Sun rise/set/twilight within about a minute of published almanacs outside the polar circles;
/// Moon rise/set within a few minutes; positions within about 0.1°.
/// ΔT is a constant 69 s (see `AstroMath.deltaT`).
public struct Astronomy: Ephemeris, Sendable {
    public init() {}

    /// Sampling interval used to bracket altitude crossings before bisection.
    private static let sampleStep: Double = 600

    // MARK: Sun

    public func sunPosition(at date: Date, coordinate: Coordinate) -> SkyPosition {
        let jd = AstroMath.julianDay(date)
        let sun = SolarCoordinates(T: AstroMath.centuriesTT(jdUT: jd))
        let h = sun.horizontal(jdUT: jd, latitude: coordinate.latitude, longitudeEast: coordinate.longitude)
        return SkyPosition(altitude: h.altitude + AstroMath.refraction(trueAltitude: h.altitude), azimuth: h.azimuth)
    }

    /// Events are crossings of the geometric (unrefracted) centre altitude: −0.833° sunrise/sunset
    /// (refraction 34′ + semi-diameter 16′), −6°/−12°/−18° twilights, +6° golden-hour boundary.
    /// Morning events are rising crossings before solar noon and evening events are setting crossings after it
    /// (so the tail of the previous evening's twilight at local midnight is not mistaken for dusk). If a threshold
    /// is crossed more than once on one side of noon (rare, near the polar circles) the first rising crossing and
    /// the last setting crossing are used.
    public func sunEvents(on day: LocalDay, at coordinate: Coordinate, in timeZone: TimeZone) -> SunEvents {
        let start = day.start(in: timeZone).timeIntervalSince1970
        let end = day.adding(days: 1).start(in: timeZone).timeIntervalSince1970
        let lat = coordinate.latitude, lon = coordinate.longitude
        let step = Self.sampleStep
        let n = max(2, Int((end - start) / step).advanced(by: 1))
        let dt = (end - start) / Double(n)
        let alt: (Double) -> Double = { SolarCoordinates.altitude(unix: $0, latitude: lat, longitude: lon) }
        let values = (0...n).map { alt(start + Double($0) * dt) }

        // Solar noon: maximum altitude, refined by ternary search around the best sample.
        let best = values.indices.max(by: { values[$0] < values[$1] })!
        var lo = start + Double(max(0, best - 1)) * dt
        var hi = start + Double(min(n, best + 1)) * dt
        for _ in 0..<40 {
            let m1 = lo + (hi - lo) / 3, m2 = hi - (hi - lo) / 3
            if alt(m1) < alt(m2) { lo = m1 } else { hi = m2 }
        }
        let noon = Date(timeIntervalSince1970: (lo + hi) / 2)

        func pair(_ threshold: Double) -> (rise: Date?, set: Date?) {
            let c = AstroMath.crossings(t0: start, step: dt, values: values, threshold: threshold, f: alt)
            let nz = noon.timeIntervalSince1970
            let rise = c.first(where: { $0.rising && $0.time < nz })?.time
            let set = c.last(where: { !$0.rising && $0.time > nz })?.time
            return (rise.map { Date(timeIntervalSince1970: $0) }, set.map { Date(timeIntervalSince1970: $0) })
        }

        let horizon = -0.833
        let kind: SunEvents.DayKind
        if values.min()! > horizon { kind = .polarDay }
        else if values.max()! < horizon { kind = .polarNight }
        else { kind = .normal }

        let rs = pair(horizon), civil = pair(-6), nautical = pair(-12), astro = pair(-18), golden = pair(6)
        return SunEvents(day: day, kind: kind, solarNoon: noon,
                         astronomicalDawn: astro.rise, nauticalDawn: nautical.rise, civilDawn: civil.rise,
                         sunrise: rs.rise, goldenMorningEnd: golden.rise, goldenEveningStart: golden.set,
                         sunset: rs.set, civilDusk: civil.set, nauticalDusk: nautical.set, astronomicalDusk: astro.set)
    }

    // MARK: Moon

    public func moonPosition(at date: Date, coordinate: Coordinate) -> SkyPosition {
        let jd = AstroMath.julianDay(date)
        let moon = LunarCoordinates(T: AstroMath.centuriesTT(jdUT: jd))
        let h = moon.topocentric(jdUT: jd, latitude: coordinate.latitude, longitudeEast: coordinate.longitude)
        return SkyPosition(altitude: h.altitude + AstroMath.refraction(trueAltitude: h.altitude), azimuth: h.azimuth)
    }

    public func moonPhase(at date: Date) -> MoonPhase {
        let T = AstroMath.centuriesTT(jdUT: AstroMath.julianDay(date))
        return LunarCoordinates(T: T).phase(sun: SolarCoordinates(T: T))
    }

    /// Rise and set are crossings where the Moon's upper limb meets the apparent horizon: the topocentric
    /// centre altitude equals −(34′ refraction + 0.2725·π) where π is the horizontal parallax (~0.95°), i.e.
    /// about −0.83°. This is identical to the almanac convention of a geocentric altitude of
    /// h0 = 0.7275·π − 34′ ≈ +0.125°. The first rise and first set of the local day are reported.
    public func moonEvents(on day: LocalDay, at coordinate: Coordinate, in timeZone: TimeZone) -> MoonEvents {
        let start = day.start(in: timeZone).timeIntervalSince1970
        let end = day.adding(days: 1).start(in: timeZone).timeIntervalSince1970
        let lat = coordinate.latitude, lon = coordinate.longitude
        let n = max(2, Int((end - start) / Self.sampleStep).advanced(by: 1))
        let dt = (end - start) / Double(n)
        // Topocentric centre altitude relative to the rise/set threshold; zero crossing = moonrise/set.
        let g: (Double) -> Double = { t in
            let jd = t / 86_400 + 2_440_587.5
            let m = LunarCoordinates(T: AstroMath.centuriesTT(jdUT: jd))
            let h = m.topocentric(jdUT: jd, latitude: lat, longitudeEast: lon).altitude
            return h + 34.0 / 60 + 0.2725 * m.parallax
        }
        let values = (0...n).map { g(start + Double($0) * dt) }
        let c = AstroMath.crossings(t0: start, step: dt, values: values, threshold: 0, f: g)
        let rise = c.first(where: { $0.rising })?.time
        let set = c.first(where: { !$0.rising })?.time
        let up = c.isEmpty && values[0] >= 0
        let down = c.isEmpty && values[0] < 0
        return MoonEvents(day: day, rise: rise.map { Date(timeIntervalSince1970: $0) },
                          set: set.map { Date(timeIntervalSince1970: $0) }, alwaysUp: up, alwaysDown: down)
    }
}
