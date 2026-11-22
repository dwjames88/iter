import Testing
import Foundation
import IterModel
@testable import IterAstro

/// The Milky Way core. Independent references used here:
/// - Sgr A* J2000 RA 17h45m40.04s, Dec −29°00′28.1″ (Reid and Brunthaler 2004; the IAU galactic centre direction).
/// - Meridian geometry: transit altitude = 90° − |φ − δ|, azimuth 180° (north of the zenith never occurs for δ < φ).
/// - Transit instant: the core crosses the meridian when local sidereal time equals its RA of date. The test computes
///   GMST itself from the IAU 1982 polynomial (Meeus 12.4, ignoring the 1 s equation of the equinoxes) and the RA of
///   date from the annual-precession rates m = 3.075 s, n = 1.336 s (Meeus 21.1), with no shared code with the source.
@Suite("Galactic centre")
struct GalacticCentreTests {
    /// Moon always at `moonAltitude`, sun delegated to the real ephemeris.
    struct FakeEphemeris: Ephemeris {
        var moonAltitude: Double
        let real = Astronomy()
        func sunEvents(on day: LocalDay, at coordinate: Coordinate, in timeZone: TimeZone) -> SunEvents {
            real.sunEvents(on: day, at: coordinate, in: timeZone)
        }
        func sunPosition(at date: Date, coordinate: Coordinate) -> SkyPosition { real.sunPosition(at: date, coordinate: coordinate) }
        func moonPosition(at date: Date, coordinate: Coordinate) -> SkyPosition { SkyPosition(altitude: moonAltitude, azimuth: 180) }
        func moonPhase(at date: Date) -> MoonPhase { real.moonPhase(at: date) }
        func moonEvents(on day: LocalDay, at coordinate: Coordinate, in timeZone: TimeZone) -> MoonEvents {
            real.moonEvents(on: day, at: coordinate, in: timeZone)
        }
    }

    static let denver = TimeZone(identifier: "America/Denver")!
    static let arches = Coordinate(latitude: 38.73, longitude: -109.59)

    static func utc(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    /// A day-long span starting at `start`, examined every minute.
    static func peak(near start: Date, at c: Coordinate, hours: Double = 24) -> MilkyWayVisibility {
        Astronomy().galacticVisibility(over: TimeSpan(start: start, end: start.addingTimeInterval(hours * 3600)),
                                       at: c, minimumAltitude: 10, stepMinutes: 1)
    }

    @Test func constantsMatchSgrAStar() {
        #expect(abs(GalacticCentre.rightAscensionJ2000 - 266.41683) < 1e-4)
        #expect(abs(GalacticCentre.declinationJ2000 - -29.00781) < 1e-4)
    }

    @Test func transitAltitudeAndAzimuthFollowDeclination() {
        // 90 − |38.5 − (−29.0)| = 22.5°, plus about 0.04° refraction. Precession since J2000 moves Dec by under 0.01°.
        let c = Coordinate(latitude: 38.5, longitude: -100)
        let v = Self.peak(near: Self.utc(2026, 6, 15), at: c)
        #expect(abs(v.peakAltitude - 22.5) < 0.2)
        #expect(abs(v.peakAzimuth - 180) < 1.0)
    }

    @Test func transitHappensAtLocalSiderealTimeEqualToRA() {
        let c = Self.arches
        let start = Self.utc(2026, 6, 15, 12)   // a day starting at noon UT, so one transit lies inside
        let v = Self.peak(near: start, at: c)

        // Independent expectation. RA of date = RA2000 + (m + n sinα tanδ)·years.
        let years = (start.timeIntervalSince1970 / 86_400 + 2_440_587.5 - 2_451_545.0) / 365.25
        let a0 = 266.41683 * Double.pi / 180, d0 = -29.00781 * Double.pi / 180
        let dRA = (3.075 + 1.336 * sin(a0) * tan(d0)) * 15 / 3600 * years    // degrees
        let ra = 266.41683 + dRA
        func gmst(_ t: Date) -> Double {
            let d = t.timeIntervalSince1970 / 86_400 + 2_440_587.5 - 2_451_545.0
            let g = 280.46061837 + 360.98564736629 * d
            return g - 360 * floor(g / 360)
        }
        func lstError(_ t: Date) -> Double {            // degrees, wrapped to ±180
            var e = gmst(t) + c.longitude - ra
            e -= 360 * (e / 360).rounded()
            return e
        }
        // Newton-style solve: LST advances 360.9856°/day, so 1° of error is 3.99 minutes.
        var t = Self.utc(2026, 6, 16, 6)
        for _ in 0..<5 { t = t.addingTimeInterval(-lstError(t) / 360.98564736629 * 86_400) }
        // Rough almanac check of the independent solve itself: mid-June the core transits near 07:30 UTC
        // (01:30 MDT) at Arches, about an hour and a half after local midnight.
        #expect(abs(t.timeIntervalSince(Self.utc(2026, 6, 16, 7, 30))) < 30 * 60)
        // The found peak is that instant to within the one-minute step plus the 1 s equation of equinoxes.
        #expect(abs(v.peakTime.timeIntervalSince(t)) < 3 * 60)
    }

    @Test func neverRisesFromFarNorth() {
        let c = Coordinate(latitude: 70, longitude: 20)   // 90 − |70 + 29| = −9°
        let v = Self.peak(near: Self.utc(2026, 6, 15), at: c)
        #expect(v.peakAltitude < 0)
        #expect(v.peakAltitude > -12)
        #expect(!v.isVisible)
    }

    @Test func nearZenithFromTheSouthernHemisphere() {
        // Siding Spring: 90 − |−31.27 + 29.0| = 87.7° at transit.
        let c = Coordinate(latitude: -31.27, longitude: 149.07)
        let v = Self.peak(near: Self.utc(2026, 6, 15), at: c)
        #expect(v.peakAltitude >= 85)
        #expect(abs(v.peakAltitude - 87.7) < 0.3)
    }

    @Test func juneNightIsVisibleAtADarkSite() {
        let day = LocalDay(year: 2026, month: 6, day: 15)
        let span = TimeSpan(start: day.at(hour: 20, in: Self.denver), end: day.adding(days: 1).at(hour: 6, in: Self.denver))
        let v = GalacticCentre.visibility(over: span, at: Self.arches, ephemeris: Astronomy())
        #expect(v.isVisible)
        let dark = try! #require(v.coreUpInDark)
        #expect(dark.duration > 3 * 3600)
        #expect(span.contains(dark.start) && span.contains(dark.end))
        // The core transits near 01:30 MDT in mid-June (see the sidereal test); the sample step is 10 minutes.
        #expect(abs(v.peakTime.timeIntervalSince(day.adding(days: 1).at(hour: 1, minute: 30, in: Self.denver))) < 30 * 60)
        #expect(v.peakAltitude > 20 && v.peakAltitude < 25)
    }

    @Test func decemberNightHasNoCore() {
        // In December the core is within a few hours of the sun, so it is never up in astronomical dark.
        let day = LocalDay(year: 2026, month: 12, day: 15)
        let span = TimeSpan(start: day.at(hour: 17, in: Self.denver), end: day.adding(days: 1).at(hour: 8, in: Self.denver))
        let v = GalacticCentre.visibility(over: span, at: Self.arches, ephemeris: Astronomy())
        #expect(v.coreUpInDark == nil)
        #expect(v.bestWindow == nil)
        #expect(!v.isVisible)
    }

    @Test func bestWindowIsNilWhenTheMoonIsUpAllNight() {
        let day = LocalDay(year: 2026, month: 6, day: 15)
        let span = TimeSpan(start: day.at(hour: 20, in: Self.denver), end: day.adding(days: 1).at(hour: 6, in: Self.denver))
        let v = GalacticCentre.visibility(over: span, at: Self.arches, ephemeris: FakeEphemeris(moonAltitude: 30))
        #expect(v.coreUpInDark != nil)
        #expect(v.bestWindow == nil)
    }

    @Test func bestWindowEqualsDarkRunWhenTheMoonIsDown() {
        let day = LocalDay(year: 2026, month: 6, day: 15)
        let span = TimeSpan(start: day.at(hour: 20, in: Self.denver), end: day.adding(days: 1).at(hour: 6, in: Self.denver))
        let v = GalacticCentre.visibility(over: span, at: Self.arches, ephemeris: FakeEphemeris(moonAltitude: -20))
        #expect(v.bestWindow != nil)
        #expect(v.bestWindow == v.coreUpInDark)
    }

    @Test func realFullMoonLeavesNoBestWindow() {
        // Full moon 2026-06-29/30 (checked against the existing moon code): the moon is up through the dark.
        let day = LocalDay(year: 2026, month: 6, day: 29)
        let span = TimeSpan(start: day.at(hour: 20, in: Self.denver), end: day.adding(days: 1).at(hour: 6, in: Self.denver))
        let eph = Astronomy()
        #expect(eph.moonPhase(at: span.midpoint).illumination > 0.97)
        let v = GalacticCentre.visibility(over: span, at: Self.arches, ephemeris: eph)
        #expect(v.coreUpInDark != nil)
        #expect(v.bestWindow == nil)   // moon above the horizon for the whole of the core's dark run
    }

    @Test func windowAcrossASpringForwardDSTChangeIsRealElapsedTime() {
        // America/Denver springs forward at 02:00 on 2026-03-08: 22:00 to 06:00 local is seven elapsed hours.
        let day = LocalDay(year: 2026, month: 3, day: 7)
        let span = TimeSpan(start: day.at(hour: 22, in: Self.denver), end: day.adding(days: 1).at(hour: 6, in: Self.denver))
        #expect(span.duration == 7 * 3600)
        let v = GalacticCentre.visibility(over: span, at: Self.arches, ephemeris: Astronomy())
        #expect(span.contains(v.peakTime))
        // The core rises in the small hours in March, so the run ends with the span or at astronomical dawn.
        let dark = try! #require(v.coreUpInDark)
        #expect(span.contains(dark.start) && span.contains(dark.end))
        #expect(dark.duration > 0)
        // The same absolute span described in UTC gives the identical answer.
        let utcSpan = TimeSpan(start: span.start, end: span.end)
        #expect(GalacticCentre.visibility(over: utcSpan, at: Self.arches, ephemeris: Astronomy()) == v)
    }

    @Test func stepAndDegenerateSpansAreSafe() {
        let t = Self.utc(2026, 6, 16, 6)
        let v = GalacticCentre.visibility(over: TimeSpan(start: t, end: t), at: Self.arches, ephemeris: Astronomy(), stepMinutes: 0)
        #expect(v.peakTime == t)
    }
}

extension Astronomy {
    fileprivate func galacticVisibility(over span: TimeSpan, at c: Coordinate, minimumAltitude: Double,
                                        stepMinutes: Int) -> MilkyWayVisibility {
        GalacticCentre.visibility(over: span, at: c, ephemeris: self, minimumAltitude: minimumAltitude, stepMinutes: stepMinutes)
    }
}
