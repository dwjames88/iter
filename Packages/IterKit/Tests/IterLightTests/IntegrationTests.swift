import Foundation
import Testing
import IterCore
import IterAstro
@testable import IterLight

/// The engine with the real ephemeris: windows land where the published sun times say they should.
@Suite struct EngineWithAstronomyTests {
    let engine = LightEngine(ephemeris: Astronomy())
    let mesa = Spot(id: "mesa-arch", name: "Mesa Arch", locality: "Canyonlands National Park, UT",
                    coordinate: Coordinate(latitude: 38.3890, longitude: -109.8677), timeZoneIdentifier: "America/Denver",
                    category: .desert, bestLight: [.sunrise], origin: .curated)

    @Test func sunriseWindowStartsAtSunrise() throws {
        let day = LocalDay(year: 2026, month: 10, day: 7)
        let windows = engine.windows(for: mesa, on: day)
        #expect(windows.map(\.kind) == [.blueMorning, .goldenMorning, .goldenEvening, .blueEvening, .night])
        let golden = try #require(windows.first { $0.kind == .goldenMorning })
        let zone = mesa.timeZone
        let c = Calendar.current.dateComponents(in: zone, from: golden.span.start)
        // Sunrise at Mesa Arch on 7 Oct 2026 is about 07:19 MDT (USNO, Moab area): within a few minutes.
        let minutes = c.hour! * 60 + c.minute!
        #expect(abs(minutes - (7 * 60 + 19)) <= 4)
        // Golden hour runs to +6°, roughly 30–45 minutes at this latitude in October.
        #expect((25 * 60...50 * 60).contains(golden.span.duration))
    }

    @Test func noForecastMeansNoScoreButRealTimes() {
        let light = engine.dayLight(for: mesa, on: LocalDay(year: 2026, month: 10, day: 7), forecast: nil,
                                    unavailable: .weatherServiceNotEnabled, now: LocalDay(year: 2026, month: 10, day: 6).noon(in: mesa.timeZone))
        #expect(light.windows.count == 5)
        #expect(light.windows.allSatisfy { $0.score == nil })
        #expect(light.sun.sunrise != nil && light.sun.sunset != nil)
    }

    let tromso = Spot(id: "t", name: "Tromsø", locality: "", coordinate: Coordinate(latitude: 69.65, longitude: 18.96),
                      timeZoneIdentifier: "Europe/Oslo", category: .landscape, origin: .user)

    @Test func polarNightKeepsTheNoonBlueHour() {
        let w = engine.windows(for: tromso, on: LocalDay(year: 2026, month: 12, day: 21))
        #expect(!w.contains { $0.kind.isGolden })
        #expect(w.map(\.kind).prefix(2) == [.blueMorning, .blueEvening])
        // Civil twilight runs roughly 09:30–13:50 local around the solstice.
        let blue = w.filter { $0.kind.isBlue }.reduce(0) { $0 + $1.span.duration }
        #expect((3 * 3600...6 * 3600).contains(blue))
    }

    @Test func midnightSunHasAGoldenEveningAndNoBlueHour() throws {
        let w = engine.windows(for: tromso, on: LocalDay(year: 2026, month: 6, day: 21))
        #expect(!w.contains { $0.kind.isBlue })
        let golden = try #require(w.first { $0.kind == .goldenEvening })
        #expect(golden.span.duration > 2 * 3600)
    }
}
