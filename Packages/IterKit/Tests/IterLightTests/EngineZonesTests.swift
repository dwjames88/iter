import Foundation
import Testing
import IterCore
import IterAstro
@testable import IterLight

/// The engine's windows land at the almanac's times for the SPOT's zone, on days the clocks change, in both
/// hemispheres, away from the device's zone, across the date line and near the poles.
/// Nothing in IterLight or IterAstro reads `TimeZone.current` or `Calendar.current`; these tests compare against fixed-offset
/// USNO times, so they would fail on any machine whose zone leaked in (unless it happened to be the spot's).
@Suite struct EngineZonesTests {
    let engine = LightEngine(ephemeris: Astronomy())

    static func spot(_ id: String, _ lat: Double, _ lon: Double, _ zone: String) -> Spot {
        Spot(id: id, name: id, locality: "", coordinate: Coordinate(latitude: lat, longitude: lon), timeZoneIdentifier: zone,
             category: .landscape, origin: .user)
    }

    static let la = spot("la", 34.05, -118.24, "America/Los_Angeles")
    static let london = spot("london", 51.5, -0.12, "Europe/London")
    static let sydney = spot("sydney", -33.87, 151.21, "Australia/Sydney")
    static let auckland = spot("auckland", -36.85, 174.76, "Pacific/Auckland")
    static let phoenix = spot("phoenix", 33.45, -112.07, "America/Phoenix")

    struct Case: Sendable {
        let label: String, spot: Spot, day: String, offset: Int
        let civilDawn: String, sunrise: String, sunset: String, civilDusk: String
        let hoursInDay: Int
    }

    /// USNO Astronomical Applications `rstt/oneday` (https://aa.usno.navy.mil/api/rstt/oneday?date=D&coords=LAT,LON&tz=OFFSET),
    /// fetched 2026-10-07, with the UTC offset in force at sunrise and sunset (the clocks change at night).
    static let cases: [Case] = [
        Case(label: "LA spring forward", spot: la, day: "2026-03-08", offset: -7, civilDawn: "06:48", sunrise: "07:12", sunset: "18:55", civilDusk: "19:20", hoursInDay: 23),
        Case(label: "LA fall back", spot: la, day: "2026-11-01", offset: -8, civilDawn: "05:47", sunrise: "06:13", sunset: "17:00", civilDusk: "17:26", hoursInDay: 25),
        Case(label: "London spring forward", spot: london, day: "2026-03-29", offset: 1, civilDawn: "06:09", sunrise: "06:43", sunset: "19:29", civilDusk: "20:02", hoursInDay: 23),
        Case(label: "London fall back", spot: london, day: "2026-10-25", offset: 0, civilDawn: "06:07", sunrise: "06:42", sunset: "16:47", civilDusk: "17:21", hoursInDay: 25),
        Case(label: "Sydney spring forward", spot: sydney, day: "2026-10-04", offset: 11, civilDawn: "06:04", sunrise: "06:29", sunset: "19:00", civilDusk: "19:25", hoursInDay: 23),
        Case(label: "Sydney fall back", spot: sydney, day: "2026-04-05", offset: 10, civilDawn: "05:45", sunrise: "06:10", sunset: "17:45", civilDusk: "18:10", hoursInDay: 25),
        Case(label: "Auckland spring forward", spot: auckland, day: "2026-09-27", offset: 13, civilDawn: "06:38", sunrise: "07:04", sunset: "19:21", civilDusk: "19:47", hoursInDay: 23),
        Case(label: "Auckland fall back", spot: auckland, day: "2026-04-05", offset: 12, civilDawn: "06:11", sunrise: "06:37", sunset: "18:10", civilDusk: "18:35", hoursInDay: 25),
        Case(label: "Auckland ordinary day", spot: auckland, day: "2026-10-07", offset: 13, civilDawn: "06:23", sunrise: "06:49", sunset: "19:30", civilDusk: "19:56", hoursInDay: 24),
        Case(label: "Phoenix (no DST)", spot: phoenix, day: "2026-10-07", offset: -7, civilDawn: "06:02", sunrise: "06:27", sunset: "18:04", civilDusk: "18:29", hoursInDay: 24),
    ]

    static func at(_ day: String, _ hhmm: String, offset: Int) -> Date {
        let p = hhmm.split(separator: ":").map { Int($0)! }
        return LocalDay(iso: day)!.at(hour: p[0], minute: p[1], in: TimeZone(secondsFromGMT: offset * 3600)!)
    }

    @Test(arguments: cases)
    func windowsFollowTheSpotsClock(c: Case) throws {
        let day = LocalDay(iso: c.day)!
        let zone = c.spot.timeZone
        // The day itself is 23, 24 or 25 hours long.
        #expect(day.adding(days: 1).start(in: zone).timeIntervalSince(day.start(in: zone)) == Double(c.hoursInDay) * 3600)

        let light = engine.dayLight(for: c.spot, on: day, forecast: nil, unavailable: nil, now: day.start(in: zone))
        #expect(light.windows.map(\.kind) == [.blueMorning, .goldenMorning, .goldenEvening, .blueEvening, .night])
        #expect(light.timeZoneIdentifier == c.spot.timeZoneIdentifier && light.day == day)
        let w = { (k: LightWindowKind) in light.window(k)!.span }
        let want = { (hhmm: String) in Self.at(c.day, hhmm, offset: c.offset) }
        let tolerance: TimeInterval = 90   // USNO rounds to the minute
        #expect(abs(w(.blueMorning).start.timeIntervalSince(want(c.civilDawn))) <= tolerance, "\(c.label) civil dawn")
        #expect(abs(w(.goldenMorning).start.timeIntervalSince(want(c.sunrise))) <= tolerance, "\(c.label) sunrise")
        #expect(abs(w(.goldenEvening).end.timeIntervalSince(want(c.sunset))) <= tolerance, "\(c.label) sunset")
        #expect(abs(w(.blueEvening).end.timeIntervalSince(want(c.civilDusk))) <= tolerance, "\(c.label) civil dusk")

        // The windows join up and sit on the spot's calendar day.
        #expect(w(.blueMorning).end == w(.goldenMorning).start)
        #expect(w(.goldenEvening).end == w(.blueEvening).start)
        for window in light.windows {
            #expect(LocalDay(window.span.start, in: zone) == day, "\(c.label) \(window.kind) starts on the spot's day")
        }
        // Night is 3 hours of absolute time (not 3 wall-clock hours) or ends at the next dawn.
        let night = w(.night)
        #expect(night.duration <= 3 * 3600 && night.duration > 0)
        #expect(night.start == light.sun.astronomicalDusk)
    }

    @Test func dstDayNextEventIsStillTheNextRealEvent() throws {
        // Spring forward in Los Angeles: at 01:30 PST (a minute before the gap) the next event is that morning's
        // sunrise at 07:12 PDT, not an hour out either way.
        let day = LocalDay(year: 2026, month: 3, day: 8)
        let now = Date(timeIntervalSince1970: Self.at("2026-03-08", "01:30", offset: -8).timeIntervalSince1970)
        let next = try #require(engine.nextEvent(for: Self.la, forecast: nil, unavailable: nil, now: now))
        #expect(next.day == day && next.window.kind == .goldenMorning)
        #expect(abs(next.window.span.start.timeIntervalSince(Self.at("2026-03-08", "07:12", offset: -7))) <= 90)
        // Fall back: 01:30 PDT (first pass) and 01:30 PST (second pass) are an hour apart and both resolve to the same event.
        let first = Self.at("2026-11-01", "01:30", offset: -7), second = Self.at("2026-11-01", "01:30", offset: -8)
        #expect(second.timeIntervalSince(first) == 3600)
        let a = try #require(engine.nextEvent(for: Self.la, forecast: nil, unavailable: nil, now: first))
        let b = try #require(engine.nextEvent(for: Self.la, forecast: nil, unavailable: nil, now: second))
        #expect(a.window.span == b.window.span && a.day == LocalDay(year: 2026, month: 11, day: 1))
    }

    // MARK: Zones other than the device's

    @Test func eachSpotReadsItsOwnDayAtTheSameInstant() throws {
        // 2026-10-07 12:00 UTC: 01:00 on the 8th in Auckland (UTC+13), 05:00 on the 7th in Phoenix (UTC-7).
        let now = Date(timeIntervalSince1970: 1_791_374_400)
        #expect(LocalDay(now, in: Self.auckland.timeZone) == LocalDay(year: 2026, month: 10, day: 8))
        #expect(LocalDay(now, in: Self.phoenix.timeZone) == LocalDay(year: 2026, month: 10, day: 7))
        let a = try #require(engine.nextEvent(for: Self.auckland, forecast: nil, unavailable: nil, now: now))
        let p = try #require(engine.nextEvent(for: Self.phoenix, forecast: nil, unavailable: nil, now: now))
        #expect(a.day == LocalDay(year: 2026, month: 10, day: 8) && a.window.kind == .goldenMorning)
        #expect(p.day == LocalDay(year: 2026, month: 10, day: 7) && p.window.kind == .goldenMorning)
        // Auckland's sunrise is 06:49 on the 8th; Phoenix's is 06:27 on the 7th (USNO, tz +13 and -7).
        #expect(abs(a.window.span.start.timeIntervalSince(Self.at("2026-10-08", "06:47", offset: 13))) <= 5 * 60)
        #expect(abs(p.window.span.start.timeIntervalSince(Self.at("2026-10-07", "06:27", offset: -7))) <= 90)
    }

    @Test func aCoordinateWithAnotherZoneGivesTheSameSunOnTheSameClockDay() {
        // The zone only picks the day boundaries: the same place read in two zones a whole day apart differs only in
        // which instants "today" covers. Phoenix and Los Angeles clocks at the same coordinate agree on sunrise.
        let phx = Self.spot("a", 33.45, -112.07, "America/Phoenix"), lax = Self.spot("b", 33.45, -112.07, "America/Los_Angeles")
        let day = LocalDay(year: 2026, month: 7, day: 1)   // both on UTC-7 in July
        let a = engine.windows(for: phx, on: day), b = engine.windows(for: lax, on: day)
        #expect(a.map(\.span) == b.map(\.span))
    }

    @Test func dateLineSpotsLiveOnDifferentDaysAtTheSameInstant() throws {
        let kiritimati = Self.spot("kiri", 1.87, -157.4, "Pacific/Kiritimati")      // UTC+14
        let pago = Self.spot("pago", -14.28, -170.7, "Pacific/Pago_Pago")           // UTC-11
        let now = Date(timeIntervalSince1970: 1_791_374_400)                         // 2026-10-07 12:00 UTC
        #expect(LocalDay(now, in: kiritimati.timeZone) == LocalDay(year: 2026, month: 10, day: 8))
        #expect(LocalDay(now, in: pago.timeZone) == LocalDay(year: 2026, month: 10, day: 7))
        for spot in [kiritimati, pago] {
            let zone = spot.timeZone
            for hours in stride(from: 0.0, to: 48, by: 3) {
                let t = now.addingTimeInterval(hours * 3600)
                let next = try #require(engine.nextEvent(for: spot, forecast: nil, unavailable: nil, now: t))
                let today = LocalDay(t, in: zone)
                #expect(next.window.span.end > t)
                #expect((0...3).contains(today.days(until: next.day)))
                #expect(LocalDay(next.window.span.start, in: zone) == next.day)
            }
        }
    }

    // MARK: Poles

    @Test(arguments: [("tromso", 69.65, 18.96, "Europe/Oslo"), ("longyearbyen", 78.22, 15.65, "Arctic/Longyearbyen")])
    func polarYearKeepsEveryDayConsistent(id: String, lat: Double, lon: Double, zone: String) {
        let spot = Self.spot(id, lat, lon, zone)
        var day = LocalDay(year: 2026, month: 1, day: 1)
        var sawPolarDay = false, sawPolarNight = false
        for _ in 0..<365 {
            let light = engine.dayLight(for: spot, on: day, forecast: nil, unavailable: nil, now: day.noon(in: spot.timeZone))
            let starts = light.windows.map(\.span.start)
            #expect(starts == starts.sorted(), "\(id) \(day) windows chronological")
            #expect(light.windows.allSatisfy { $0.span.duration > 0 }, "\(id) \(day) no empty window")
            #expect(Set(light.windows.map(\.kind)).count == light.windows.count, "\(id) \(day) one window per kind")
            switch light.sun.kind {
            case .polarDay:
                sawPolarDay = true
                #expect(!light.windows.contains { $0.kind.isBlue || $0.kind == .goldenMorning }, "\(id) \(day) midnight sun")
                #expect(light.windows.allSatisfy { $0.kind == .goldenEvening })
            case .polarNight:
                sawPolarNight = true
                #expect(!light.windows.contains { $0.kind.isGolden }, "\(id) \(day) polar night")
            case .normal:
                break
            }
            // Night, when present, starts at astronomical dusk and never runs past three hours.
            if let night = light.window(.night) {
                #expect(night.span.duration <= 3 * 3600)
                #expect(night.span.start == light.sun.astronomicalDusk)
            }
            day = day.adding(days: 3)
        }
        #expect(sawPolarDay && sawPolarNight)
    }

    @Test func tromsoAlwaysHasANextEvent() throws {
        let spot = Self.spot("tromso", 69.65, 18.96, "Europe/Oslo")
        var day = LocalDay(year: 2026, month: 1, day: 1)
        for _ in 0..<120 {
            for hour in [1, 7, 12, 18, 23] {
                let now = day.at(hour: hour, in: spot.timeZone)
                let next = try #require(engine.nextEvent(for: spot, forecast: nil, unavailable: nil, now: now), "\(day) \(hour)h")
                #expect(next.window.kind != .night && next.window.span.end > now)
            }
            day = day.adding(days: 3)
        }
    }

    @Test func midwinterLongyearbyenHasNoDaytimeWindowAtAll() {
        // The sun's noon altitude is about -11.6 degrees, so civil twilight never happens: only night remains, and
        // nextEvent says so with nil rather than a night window or an invented one.
        let spot = Self.spot("longyearbyen", 78.22, 15.65, "Arctic/Longyearbyen")
        let day = LocalDay(year: 2026, month: 12, day: 21)
        let w = engine.windows(for: spot, on: day)
        #expect(w.allSatisfy { $0.kind == .night })
        #expect(engine.nextEvent(for: spot, forecast: nil, unavailable: nil, now: day.noon(in: spot.timeZone)) == nil)
    }

    @Test func tromsoTransitionDaysHaveOnlySomeWindows() throws {
        // Around 18 May the midnight sun starts; around 26 July it ends. On the days either side of the first day the
        // sun stays up all day, golden hour is the dip below 6 degrees and there is no blue hour.
        let spot = Self.spot("tromso", 69.65, 18.96, "Europe/Oslo")
        var firstPolarDay: LocalDay?
        var day = LocalDay(year: 2026, month: 5, day: 10)
        while day < LocalDay(year: 2026, month: 5, day: 30) {
            if engine.dayLight(for: spot, on: day, forecast: nil, unavailable: nil, now: day.noon(in: spot.timeZone)).sun.kind == .polarDay {
                firstPolarDay = day; break
            }
            day = day.adding(days: 1)
        }
        let first = try #require(firstPolarDay)
        #expect((15...21).contains(first.day) && first.month == 5)
        // Four days earlier the sun still sets and rises: both golden hours exist.
        let setting = engine.windows(for: spot, on: first.adding(days: -4))
        #expect(setting.contains { $0.kind == .goldenMorning } && setting.contains { $0.kind == .goldenEvening })
        // In between, the sun rises after a short dip but no longer sets that day: there is no sunset, so (pinned, a
        // known limitation reported in the performance pass) no golden evening, though the sun does pass 6 degrees.
        let between = engine.windows(for: spot, on: first.adding(days: -1))
        #expect(between.map(\.kind) == [.goldenMorning])
        let on = engine.windows(for: spot, on: first)
        #expect(on.map(\.kind) == [.goldenEvening])
    }
}
