import Testing
import Foundation
import IterCore
@testable import IterAstro

private let astro = Astronomy()

/// Prints the observed error of a check so the maximum per group can be read from the test log.
private func observe(_ group: String, _ label: String, _ error: Double, tolerance: Double) {
    print("ERR[\(group)] \(label): \(String(format: "%.4f", error)) (tol \(tolerance))")
}

/// An instant from a wall-clock time in a fixed UTC offset (hours), as the USNO API reports with `tz=`.
private func fixed(_ day: String, _ hhmm: String, offset: Int) -> Date {
    let d = LocalDay(iso: day)!
    let p = hhmm.split(separator: ":").map { Int($0)! }
    return d.at(hour: p[0], minute: p[1], in: TimeZone(secondsFromGMT: offset * 3600)!)
}

private func minutes(_ a: Date?, _ b: Date) -> Double {
    guard let a else { return .infinity }
    return abs(a.timeIntervalSince(b)) / 60
}

private func utc(_ s: String) -> Date {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f.date(from: s)!
}

// MARK: Meeus worked examples

@Suite("Meeus worked examples")
struct MeeusTests {
    @Test func example25aSun() {
        // Meeus, Astronomical Algorithms 2nd ed., Example 25.a: 1992 Oct 13.0 TD (JDE 2448908.5).
        // Apparent longitude 199.90895 deg, apparent declination -7.78507 deg, R = 0.99766 AU.
        let s = SolarCoordinates(T: AstroMath.centuries(jde: 2_448_908.5))
        observe("meeus", "25a lambda", abs(s.apparentLongitude - 199.90895), tolerance: 0.005)
        observe("meeus", "25a delta", abs(s.delta - -7.78507), tolerance: 0.005)
        #expect(abs(s.apparentLongitude - 199.90895) < 0.005)
        #expect(abs(s.delta - -7.78507) < 0.005)
        #expect(abs(s.distanceAU - 0.99766) < 0.0001)
    }

    @Test func example47aMoon() {
        // Meeus Example 47.a: 1992 Apr 12 0h TD (JDE 2448724.5).
        // lambda 133.162655, beta -3.229126, Delta 368409.7 km, apparent lambda 133.167265, parallax 0.991990.
        // Our series is abridged, so tolerances are wider than the full theory.
        let m = LunarCoordinates(T: AstroMath.centuries(jde: 2_448_724.5))
        observe("meeus", "47a lambda", abs(m.longitude - 133.162655), tolerance: 0.02)
        observe("meeus", "47a beta", abs(m.latitude - -3.229126), tolerance: 0.02)
        observe("meeus", "47a distance km", abs(m.distanceKm - 368_409.7), tolerance: 100)
        #expect(abs(m.longitude - 133.162655) < 0.02)
        #expect(abs(m.latitude - -3.229126) < 0.02)
        #expect(abs(m.distanceKm - 368_409.7) < 100)
        #expect(abs(m.apparentLongitude - 133.167265) < 0.02)
        #expect(abs(m.parallax - 0.991990) < 0.001)
    }

    @Test func example48aPhase() {
        // Meeus Example 48.a: same instant, illuminated fraction k = 0.6786.
        let T = AstroMath.centuries(jde: 2_448_724.5)
        let p = LunarCoordinates(T: T).phase(sun: SolarCoordinates(T: T))
        observe("meeus", "48a k", abs(p.illumination - 0.6786), tolerance: 0.005)
        #expect(abs(p.illumination - 0.6786) < 0.005)
    }
}

// MARK: Rise, set, twilight vs USNO

@Suite("Sun events vs USNO")
struct SunEventTests {
    struct Case: Sendable {
        let name: String, zone: String, lat: Double, lon: Double, day: String
        /// USNO Astronomical Applications `rstt/oneday` values: civil begin, rise, set, civil end as (hh:mm, utc offset used in the request).
        let civilDawn: String, sunrise: String, sunset: String, civilDusk: String, offset: Int
    }

    static let cases: [Case] = [
        // USNO API https://aa.usno.navy.mil/api/rstt/oneday?date=...&coords=...&tz=...
        Case(name: "Moab", zone: "America/Denver", lat: 38.57, lon: -109.55, day: "2026-10-10",
             civilDawn: "06:56", sunrise: "07:23", sunset: "18:47", civilDusk: "19:14", offset: -6),
        Case(name: "Hobart", zone: "Australia/Hobart", lat: -42.88, lon: 147.33, day: "2026-12-21",
             civilDawn: "04:53", sunrise: "05:28", sunset: "20:49", civilDusk: "21:24", offset: 11),
        Case(name: "Quito", zone: "America/Guayaquil", lat: -0.18, lon: -78.47, day: "2026-03-20",
             civilDawn: "05:57", sunrise: "06:18", sunset: "18:25", civilDusk: "18:45", offset: -5),
        Case(name: "Reykjavik", zone: "Atlantic/Reykjavik", lat: 64.15, lon: -21.94, day: "2026-03-20",
             civilDawn: "06:41", sunrise: "07:29", sunset: "19:43", civilDusk: "20:31", offset: 0),
        // DST ends 2026-11-01 02:00 in the US: a 25 hour day. USNO queried with tz=-7 gave 07:20/07:51/17:57/18:28,
        // which is 06:20/06:51/16:57/17:28 PST (UTC-8), the zone the sun actually rises in that morning.
        Case(name: "Portland (DST end)", zone: "America/Los_Angeles", lat: 45.52, lon: -122.68, day: "2026-11-01",
             civilDawn: "06:20", sunrise: "06:51", sunset: "16:57", civilDusk: "17:28", offset: -8),
        Case(name: "New York", zone: "America/New_York", lat: 40.71, lon: -74.01, day: "2026-01-03",
             civilDawn: "06:50", sunrise: "07:20", sunset: "16:41", civilDusk: "17:12", offset: -5),
        Case(name: "Tokyo", zone: "Asia/Tokyo", lat: 35.68, lon: 139.69, day: "2026-07-22",
             civilDawn: "04:13", sunrise: "04:41", sunset: "18:54", civilDusk: "19:22", offset: 9),
        Case(name: "Sydney", zone: "Australia/Sydney", lat: -33.87, lon: 151.21, day: "2026-04-01",
             civilDawn: "06:42", sunrise: "07:07", sunset: "18:51", civilDusk: "19:16", offset: 11),
    ]

    @Test(arguments: cases)
    func matchesUSNO(c: Case) {
        let tz = TimeZone(identifier: c.zone)!
        let e = astro.sunEvents(on: LocalDay(iso: c.day)!, at: Coordinate(latitude: c.lat, longitude: c.lon), in: tz)
        #expect(e.kind == .normal)
        let pairs: [(String, Date?, String)] = [("civilDawn", e.civilDawn, c.civilDawn), ("sunrise", e.sunrise, c.sunrise),
                                                 ("sunset", e.sunset, c.sunset), ("civilDusk", e.civilDusk, c.civilDusk)]
        for (label, got, want) in pairs {
            let err = minutes(got, fixed(c.day, want, offset: c.offset))
            observe("usno-sun", "\(c.name) \(label)", err, tolerance: 2)
            #expect(err <= 2, "\(c.name) \(label) off by \(err) min")
        }
        // USNO reports solar transit to the minute as well.
    }

    @Test func solarNoonMatchesUSNOTransit() {
        // USNO upper transit Moab 2026-10-10 13:05 MDT (UTC-6).
        let e = astro.sunEvents(on: LocalDay(iso: "2026-10-10")!, at: Coordinate(latitude: 38.57, longitude: -109.55),
                                in: TimeZone(identifier: "America/Denver")!)
        let err = minutes(e.solarNoon, fixed("2026-10-10", "13:05", offset: -6))
        observe("usno-sun", "Moab noon", err, tolerance: 2)
        #expect(err <= 2)
    }
}

// MARK: Polar

@Suite("Polar edge cases")
struct PolarTests {
    let tromso = Coordinate(latitude: 69.65, longitude: 18.96)
    let oslo = TimeZone(identifier: "Europe/Oslo")!

    @Test func tromsoMidnightSun() {
        // USNO: Tromso 2026-06-21 sun continuously above the horizon.
        let e = astro.sunEvents(on: LocalDay(iso: "2026-06-21")!, at: tromso, in: oslo)
        #expect(e.kind == .polarDay)
        #expect(e.sunrise == nil && e.sunset == nil)
        // USNO upper transit 12:46 CEST (UTC+2).
        let err = minutes(e.solarNoon, fixed("2026-06-21", "12:46", offset: 2))
        observe("polar", "Tromso noon", err, tolerance: 2)
        #expect(err <= 2)
    }

    @Test func tromsoPolarNight() {
        // USNO: Tromso 2026-12-21 sun continuously below the horizon; civil twilight 09:31 to 13:53 CET (UTC+1).
        let e = astro.sunEvents(on: LocalDay(iso: "2026-12-21")!, at: tromso, in: oslo)
        #expect(e.kind == .polarNight)
        #expect(e.sunrise == nil && e.sunset == nil)
        #expect(e.goldenMorningEnd == nil && e.goldenEveningStart == nil)
        let a = minutes(e.civilDawn, fixed("2026-12-21", "09:31", offset: 1))
        let b = minutes(e.civilDusk, fixed("2026-12-21", "13:53", offset: 1))
        observe("polar", "Tromso civil dawn", a, tolerance: 2)
        observe("polar", "Tromso civil dusk", b, tolerance: 2)
        #expect(a <= 2 && b <= 2)
    }

    @Test func longyearbyenMidJune() {
        let e = astro.sunEvents(on: LocalDay(iso: "2026-06-15")!, at: Coordinate(latitude: 78.22, longitude: 15.65),
                                in: TimeZone(identifier: "Arctic/Longyearbyen")!)
        #expect(e.kind == .polarDay)
        #expect(e.sunrise == nil && e.sunset == nil && e.civilDawn == nil)
    }

    @Test func londonSolstice() {
        // USNO London 2026-06-21: rise 04:43, set 21:21 BST (UTC+1), civil 03:55 to 22:09.
        // The sun's midnight depression is about 15 degrees: nautical twilight exists, astronomical does not.
        let e = astro.sunEvents(on: LocalDay(iso: "2026-06-21")!, at: Coordinate(latitude: 51.5, longitude: -0.12),
                                in: TimeZone(identifier: "Europe/London")!)
        #expect(e.kind == .normal)
        #expect(e.sunset != nil && e.sunrise != nil)
        #expect(e.astronomicalDusk == nil && e.astronomicalDawn == nil)
        #expect(e.nauticalDusk != nil && e.nauticalDawn != nil)
        let errs = [minutes(e.sunrise, fixed("2026-06-21", "04:43", offset: 1)), minutes(e.sunset, fixed("2026-06-21", "21:21", offset: 1)),
                    minutes(e.civilDawn, fixed("2026-06-21", "03:55", offset: 1)), minutes(e.civilDusk, fixed("2026-06-21", "22:09", offset: 1))]
        observe("polar", "London max", errs.max()!, tolerance: 2)
        #expect(errs.allSatisfy { $0 <= 2 })
    }
}

// MARK: Positions vs JPL Horizons

@Suite("Positions vs JPL Horizons")
struct PositionTests {
    // JPL Horizons API (ssd.jpl.nasa.gov/api/horizons.api), QUANTITIES=4 (apparent azimuth/elevation, refracted),
    // topocentric from a geodetic site. Times are UT.
    struct Case: Sendable {
        let name: String, body: CelestialBody, lat: Double, lon: Double, utc: String, az: Double, alt: Double
    }
    static let cases: [Case] = [
        Case(name: "Sun Moab 14:00", body: .sun, lat: 38.57, lon: -109.55, utc: "2026-10-10T14:00:00Z", az: 103.919551, alt: 6.462330),
        Case(name: "Sun Moab 16:00", body: .sun, lat: 38.57, lon: -109.55, utc: "2026-10-10T16:00:00Z", az: 125.956358, alt: 27.574026),
        Case(name: "Sun Hobart 06:00", body: .sun, lat: -42.88, lon: 147.33, utc: "2026-12-21T06:00:00Z", az: 273.009422, alt: 38.955882),
        Case(name: "Sun Hobart 07:00", body: .sun, lat: -42.88, lon: 147.33, utc: "2026-12-21T07:00:00Z", az: 263.025981, alt: 27.999600),
        Case(name: "Sun Reykjavik 12:00", body: .sun, lat: 64.15, lon: -21.94, utc: "2026-03-20T12:00:00Z", az: 153.901787, alt: 23.503671),
        Case(name: "Sun Quito 23:00", body: .sun, lat: -0.18, lon: -78.47, utc: "2026-03-20T23:00:00Z", az: 270.152988, alt: 5.446637),
        Case(name: "Moon Moab 14:00", body: .moon, lat: 38.57, lon: -109.55, utc: "2026-10-10T14:00:00Z", az: 107.812191, alt: 5.266253),
        Case(name: "Moon Moab 16:00", body: .moon, lat: 38.57, lon: -109.55, utc: "2026-10-10T16:00:00Z", az: 129.671252, alt: 24.806602),
        Case(name: "Moon Hobart 09:00", body: .moon, lat: -42.88, lon: 147.33, utc: "2026-12-21T09:00:00Z", az: 33.891577, alt: 15.406295),
        Case(name: "Moon New York 03:00", body: .moon, lat: 40.71, lon: -74.01, utc: "2026-01-03T03:00:00Z", az: 113.377487, alt: 64.542315),
        Case(name: "Moon Portland 20:00", body: .moon, lat: 45.52, lon: -122.68, utc: "2026-11-02T20:00:00Z", az: 268.869297, alt: 20.357935),
    ]

    @Test(arguments: cases)
    func matchesHorizons(c: Case) {
        let at = utc(c.utc)
        let coord = Coordinate(latitude: c.lat, longitude: c.lon)
        let p = c.body == .sun ? astro.sunPosition(at: at, coordinate: coord) : astro.moonPosition(at: at, coordinate: coord)
        var dAz = abs(p.azimuth - c.az)
        if dAz > 180 { dAz = 360 - dAz }
        let dAlt = abs(p.altitude - c.alt)
        let group = c.body == .sun ? "pos-sun" : "pos-moon"
        let tol = c.body == .sun ? 0.2 : 0.3
        observe(group, "\(c.name) alt", dAlt, tolerance: tol)
        observe(group, "\(c.name) az", dAz, tolerance: tol)
        #expect(dAlt < tol && dAz < tol)
    }
}

// MARK: Moon events and phase

@Suite("Moon events and phase")
struct MoonTests {
    struct Case: Sendable {
        let name: String, zone: String, lat: Double, lon: Double, day: String, offset: Int, rise: String?, set: String?
    }
    // USNO rstt/oneday moondata.
    static let cases: [Case] = [
        Case(name: "Moab", zone: "America/Denver", lat: 38.57, lon: -109.55, day: "2026-10-10", offset: -6, rise: "07:27", set: "18:34"),
        Case(name: "Hobart", zone: "Australia/Hobart", lat: -42.88, lon: 147.33, day: "2026-12-21", offset: 11, rise: "17:50", set: "02:22"),
        Case(name: "Quito", zone: "America/Guayaquil", lat: -0.18, lon: -78.47, day: "2026-03-20", offset: -5, rise: "07:28", set: "19:52"),
        Case(name: "Reykjavik", zone: "Atlantic/Reykjavik", lat: 64.15, lon: -21.94, day: "2026-03-20", offset: 0, rise: "07:14", set: "22:58"),
        Case(name: "New York", zone: "America/New_York", lat: 40.71, lon: -74.01, day: "2026-01-03", offset: -5, rise: "16:56", set: "07:52"),
        Case(name: "Tromso", zone: "Europe/Oslo", lat: 69.65, lon: 18.96, day: "2026-06-21", offset: 2, rise: "12:18", set: "00:37"),
    ]

    @Test(arguments: cases)
    func riseSetMatchesUSNO(c: Case) {
        let e = astro.moonEvents(on: LocalDay(iso: c.day)!, at: Coordinate(latitude: c.lat, longitude: c.lon),
                                 in: TimeZone(identifier: c.zone)!)
        for (label, got, want) in [("rise", e.rise, c.rise), ("set", e.set, c.set)] {
            guard let want else { continue }
            let err = minutes(got, fixed(c.day, want, offset: c.offset))
            observe("usno-moon", "\(c.name) \(label)", err, tolerance: 5)
            #expect(err <= 5, "\(c.name) moon\(label) off by \(err) min")
        }
    }

    @Test func alwaysUpNearPole() {
        // USNO: Longyearbyen 2026-06-15 moon continuously above the horizon.
        let e = astro.moonEvents(on: LocalDay(iso: "2026-06-15")!, at: Coordinate(latitude: 78.22, longitude: 15.65),
                                 in: TimeZone(identifier: "Arctic/Longyearbyen")!)
        #expect(e.alwaysUp && !e.alwaysDown && e.rise == nil && e.set == nil)
        // USNO: Tromso 2026-12-21 moon continuously above the horizon.
        let t = astro.moonEvents(on: LocalDay(iso: "2026-12-21")!, at: Coordinate(latitude: 69.65, longitude: 18.96),
                                 in: TimeZone(identifier: "Europe/Oslo")!)
        #expect(t.alwaysUp)
    }

    // JPL Horizons QUANTITIES=10 (illuminated fraction, percent), UT.
    static let illumination: [IllumCase] = [
        IllumCase(when: "2026-10-10T00:00:00Z", percent: 0.54332), IllumCase(when: "2026-12-21T12:00:00Z", percent: 90.601),
        IllumCase(when: "2026-03-20T12:00:00Z", percent: 2.91871), IllumCase(when: "2026-01-03T12:00:00Z", percent: 99.88266),
    ]
    struct IllumCase: Sendable { let when: String; let percent: Double }

    @Test(arguments: illumination)
    func illuminationMatchesHorizons(c: IllumCase) {
        let when = c.when
        let expected: Double = c.percent / 100
        let p = astro.moonPhase(at: utc(when))
        observe("moon-illum", when, abs(p.illumination - expected), tolerance: 0.02)
        #expect(abs(p.illumination - expected) < 0.02)
    }

    @Test func cycleConvention() {
        // New moon 2026-10-10 ~09:50 UT (USNO closest phase), full moon 2026-10-26 ~04:12 UT, first quarter ~2026-10-18.
        let nm = astro.moonPhase(at: utc("2026-10-10T09:50:00Z"))
        #expect(nm.cycle < 0.01 || nm.cycle > 0.99)
        let fm = astro.moonPhase(at: utc("2026-10-26T04:12:00Z"))
        #expect(abs(fm.cycle - 0.5) < 0.01)
        #expect(astro.moonPhase(at: utc("2026-10-14T00:00:00Z")).isWaxing)
        #expect(!astro.moonPhase(at: utc("2026-10-30T00:00:00Z")).isWaxing)
    }
}

// MARK: Invariants and performance

@Suite("Invariants")
struct InvariantTests {
    static let places: [(String, Double, Double, String)] = [
        ("Moab", 38.57, -109.55, "America/Denver"), ("Hobart", -42.88, 147.33, "Australia/Hobart"),
        ("Quito", -0.18, -78.47, "America/Guayaquil"), ("Reykjavik", 64.15, -21.94, "Atlantic/Reykjavik"),
        ("Tromso", 69.65, 18.96, "Europe/Oslo"), ("Portland", 45.52, -122.68, "America/Los_Angeles"),
        ("Chatham", -43.95, -176.55, "Pacific/Chatham"), ("Kiritimati", 1.87, -157.4, "Pacific/Kiritimati"),
    ]

    @Test func eventsOrderedAndInsideDay() {
        var checked = 0
        for (_, lat, lon, zone) in Self.places {
            let tz = TimeZone(identifier: zone)!
            let coord = Coordinate(latitude: lat, longitude: lon)
            var day = LocalDay(year: 2026, month: 1, day: 1)
            for _ in 0..<365 {
                let e = astro.sunEvents(on: day, at: coord, in: tz)
                let lo = day.start(in: tz), hi = day.adding(days: 1).start(in: tz)
                let seq: [Date?] = [e.astronomicalDawn, e.nauticalDawn, e.civilDawn, e.sunrise, e.goldenMorningEnd,
                                    e.solarNoon, e.goldenEveningStart, e.sunset, e.civilDusk, e.nauticalDusk, e.astronomicalDusk]
                let present = seq.compactMap { $0 }
                for d in present { #expect(d >= lo && d <= hi, "\(day) outside local day") }
                #expect(zip(present, present.dropFirst()).allSatisfy { $0 <= $1 }, "\(day) at \(lat) out of order \(e)")
                let m = astro.moonEvents(on: day, at: coord, in: tz)
                for d in [m.rise, m.set].compactMap({ $0 }) { #expect(d >= lo && d <= hi) }
                checked += 1
                day = day.adding(days: 1)
            }
        }
        #expect(checked == Self.places.count * 365)
    }

    @Test func dstDaysHaveEvents() {
        // 23 hour (2026-03-08) and 25 hour (2026-11-01) days in Portland.
        let tz = TimeZone(identifier: "America/Los_Angeles")!
        for iso in ["2026-03-08", "2026-11-01"] {
            let e = astro.sunEvents(on: LocalDay(iso: iso)!, at: Coordinate(latitude: 45.52, longitude: -122.68), in: tz)
            #expect(e.kind == .normal && e.sunrise != nil && e.sunset != nil)
        }
    }

    @Test func performance365Days() {
        let tz = TimeZone(identifier: "America/Denver")!
        let coord = Coordinate(latitude: 38.57, longitude: -109.55)
        var day = LocalDay(year: 2026, month: 1, day: 1)
        let t0 = Date()
        var n = 0
        for _ in 0..<365 {
            if astro.sunEvents(on: day, at: coord, in: tz).sunrise != nil { n += 1 }
            day = day.adding(days: 1)
        }
        let dt = Date().timeIntervalSince(t0)
        print("PERF 365 sunEvents: \(dt) s")
        #expect(n == 365)
        #expect(dt < 2.0)   // generous: the budget is ~0.5 s in debug
    }
}
