import Foundation
import Testing
import IterCore
import IterAstro
@testable import IterLight

/// The list rows' "next event": the next sunrise or sunset by the spot's own clock.
@Suite struct NextEventTests {
    let engine = LightEngine(ephemeris: Astronomy())
    let denver = TimeZone(identifier: "America/Denver")!
    let day = LocalDay(year: 2026, month: 10, day: 6)

    func spot(_ id: String, lat: Double, lon: Double, zone: String) -> Spot {
        Spot(id: id, name: id, locality: "", coordinate: Coordinate(latitude: lat, longitude: lon), timeZoneIdentifier: zone,
             category: .landscape, origin: .user)
    }
    var mesa: Spot { spot("mesa", lat: 38.389, lon: -109.8677, zone: "America/Denver") }

    func golden(_ spot: Spot, _ d: LocalDay, _ kind: LightWindowKind) -> TimeSpan {
        engine.windows(for: spot, on: d).first { $0.kind == kind }!.span
    }

    @Test func beforeSunriseIsTodaysSunrise() throws {
        let rise = golden(mesa, day, .goldenMorning)
        let next = try #require(engine.nextEvent(for: mesa, forecast: nil, unavailable: nil, now: rise.start.addingTimeInterval(-3600)))
        #expect(next.day == day)
        #expect(next.window.kind == .goldenMorning)
        #expect(next.window.span == rise)
    }

    @Test func midAfternoonIsTodaysSunset() throws {
        let next = try #require(engine.nextEvent(for: mesa, forecast: nil, unavailable: nil, now: day.at(hour: 15, in: denver)))
        #expect(next.day == day)
        #expect(next.window.kind == .goldenEvening)
    }

    @Test func aWindowInProgressIsStillNextUntilItEnds() throws {
        let set = golden(mesa, day, .goldenEvening)
        let during = try #require(engine.nextEvent(for: mesa, forecast: nil, unavailable: nil, now: set.midpoint))
        #expect(during.window.kind == .goldenEvening && during.day == day)
        let after = try #require(engine.nextEvent(for: mesa, forecast: nil, unavailable: nil, now: set.end.addingTimeInterval(60)))
        #expect(after.window.kind == .goldenMorning && after.day == day.adding(days: 1))
    }

    @Test func acrossLocalMidnightTheDayIsTomorrows() throws {
        let tomorrow = day.adding(days: 1)
        for now in [day.at(hour: 23, minute: 30, in: denver), tomorrow.at(hour: 0, minute: 30, in: denver)] {
            let next = try #require(engine.nextEvent(for: mesa, forecast: nil, unavailable: nil, now: now))
            #expect(next.day == tomorrow)
            #expect(next.window.kind == .goldenMorning)
        }
    }

    @Test func theSpotsZoneDecidesTheDayNotTheMacs() throws {
        // 2026-10-06 06:00 UTC: afternoon of 6 Oct in Tokyo, evening of 5 Oct in Los Angeles.
        let now = Date(timeIntervalSince1970: 1_791_266_400)
        let utc = TimeZone(identifier: "UTC")!
        #expect(LocalDay(now, in: utc) == day)
        let tokyo = spot("tokyo", lat: 35.68, lon: 139.69, zone: "Asia/Tokyo")
        let la = spot("la", lat: 34.05, lon: -118.24, zone: "America/Los_Angeles")
        let t = try #require(engine.nextEvent(for: tokyo, forecast: nil, unavailable: nil, now: now))
        #expect(t.day == day)
        #expect(t.window.kind == .goldenEvening)
        #expect(LocalDay(t.window.span.start, in: tokyo.timeZone) == t.day)
        let l = try #require(engine.nextEvent(for: la, forecast: nil, unavailable: nil, now: now))
        // 23:00 on 5 Oct in LA: the next event is the morning of the 6th.
        #expect(l.day == day)
        #expect(l.window.kind == .goldenMorning)
        #expect(LocalDay(l.window.span.start, in: la.timeZone) == l.day)
        #expect(LocalDay(now, in: la.timeZone) == day.adding(days: -1))
    }

    @Test func polarNightFallsBackToAnyDaytimeWindow() throws {
        let tromso = spot("tromso", lat: 69.65, lon: 18.96, zone: "Europe/Oslo")
        let zone = tromso.timeZone
        let d = LocalDay(year: 2026, month: 12, day: 21)
        let next = try #require(engine.nextEvent(for: tromso, forecast: nil, unavailable: nil, now: d.at(hour: 8, in: zone)))
        #expect(next.window.kind.isBlue)
        #expect(next.window.span.end > d.at(hour: 8, in: zone))
    }

    @Test func theNextEventIsScoredFromTheForecast() throws {
        let start = day.start(in: denver)
        let hours = (0..<(8 * 24)).map { i in
            HourlyConditions(date: start.addingTimeInterval(Double(i) * 3600), cloudCover: 0.35, cloudLow: 0.05, cloudMid: 0.3, cloudHigh: 0.3,
                             precipitationChance: 0, visibilityMeters: 20_000, windSpeedKph: 5, temperatureC: 12, humidity: 0.5,
                             symbolName: "sun.max", condition: "clear")
        }
        let f = Forecast(coordinate: mesa.coordinate, hours: hours, days: [], fetchedAt: start, source: .openWeather)
        let next = try #require(engine.nextEvent(for: mesa, forecast: f, unavailable: nil, now: day.at(hour: 10, in: denver)))
        #expect(next.window.score != nil)
    }

    @Test func upcomingWindowsAreTodaysRemainingThenTomorrow() {
        let now = day.at(hour: 10, in: denver)
        let list = engine.upcomingWindows(for: mesa, forecast: nil, unavailable: nil, now: now)
        let today = list.filter { $0.day == day }
        let tomorrow = list.filter { $0.day == day.adding(days: 1) }
        #expect(list.count == today.count + tomorrow.count)
        #expect(today.map(\.window.kind) == [.goldenEvening, .blueEvening, .night])
        #expect(tomorrow.map(\.window.kind) == [.blueMorning, .goldenMorning, .goldenEvening, .blueEvening, .night])
        let starts = list.map(\.window.span.start)
        #expect(starts == starts.sorted())
    }
}
