import Foundation
import Testing
import IterModel
import IterSources
import IterSky
import IterAstro
@testable import IterConditions

/// Virtual-time scheduling harness. A fake "MET-like" source (one request per place, 0.8 s each, serial, 1 s apart) and a
/// fake "NOAA-like" batch source (cost = hours x half-degree tiles, 1.2 s each: the 50 requests a minute cap) run on a
/// virtual clock. It prints requests per provider and the virtual time to the first score and to the complete report. The
/// lead reruns it against the real NOMADS adapter by swapping `FakeBatch` for it.
@Suite("Scheduling harness", .serialized)
struct SchedulingHarness {
    struct Result: Sendable {
        var name: String
        var places: Int
        var metRequests: Int
        var noaaBatchCalls: Int
        var noaaRequests: Int
        var firstScore: Duration
        var complete: Duration
        var completeReports: Int
    }

    private func run(_ name: String, requests: (VirtualClock) -> [ConditionsRequest]) async -> Result {
        let clock = VirtualClock(now: t0)
        let met = FakeForecast(metDescriptor, clock: clock, recipe: metRecipe, latency: .milliseconds(800), spacing: .seconds(1))
        let noaa = FakeBatch(makeDescriptor("test.noaa", name: "NOAA HRRR", kinds: [.forecast], coverage: usOnly, ranks: [.forecast: 10]),
                             clock: clock, recipe: clearRecipe, perRequest: .milliseconds(1200))
        var cfg = ConditionsConfiguration()
        cfg.fetchesHorizon = false
        let sources: [any SourceDescribing] = [met, noaa]
        let deps = ConditionsDependencies(
            registry: SourceRegistry(sources: sources), cache: SourceCache(clock: clock),
            clock: clock, ephemeris: Astronomy(), configuration: cfg)
        let service = ConditionsService(deps)
        let reqs = requests(clock)
        let start = clock.now
        let timings = await clock.drive {
            var first: Date?
            var complete: [PlaceDayKey: Date] = [:]
            for await r in service.reports(for: reqs) {
                if first == nil, r.daylight.windows.contains(where: { $0.score != nil }) { first = clock.now }
                if r.tier == .complete { complete[PlaceDayKey(r.placeID, r.day)] = clock.now }
            }
            return (first, complete)
        }
        let last = timings.1.values.max() ?? start
        return Result(name: name, places: Set(reqs.map(\.place.id)).count, metRequests: met.callCount, noaaBatchCalls: noaa.batchCount,
                      noaaRequests: noaa.requestCount, firstScore: .interval((timings.0 ?? start).timeIntervalSince(start)),
                      complete: .interval(last.timeIntervalSince(start)), completeReports: timings.1.count)
    }

    struct PlaceDayKey: Hashable, Sendable {
        var id: UUID
        var day: LocalDay
        init(_ id: UUID, _ day: LocalDay) { self.id = id; self.day = day }
    }

    private func line(_ r: Result) -> String {
        func s(_ d: Duration) -> String { String(format: "%.1f s", d.timeInterval) }
        return "HARNESS \(r.name): places=\(r.places) MET requests=\(r.metRequests) NOAA batch calls=\(r.noaaBatchCalls) "
            + "NOAA requests (hours x tiles)=\(r.noaaRequests) first score=\(s(r.firstScore)) complete=\(s(r.complete))"
    }

    @Test func onePlace() async {
        let place = makePlace()
        let r = await run("1 place") { _ in [ConditionsRequest(place: place, day: localDay(of: place))] }
        print(line(r))
        #expect(r.completeReports == 1)
        #expect(r.metRequests == 1)
        #expect(r.firstScore < r.complete)
    }

    @Test func twentyPlacesInOneArea() async {
        let places = (0..<20).map { i in makePlace("P\(i)", lat: 39.40 + Double(i) * 0.03, lon: -105.2 + Double(i) * 0.02) }
        let day = localDay(of: places[0])
        let r = await run("20 places, one area") { _ in places.map { ConditionsRequest(place: $0, day: day) } }
        print(line(r))
        #expect(r.completeReports == 20)
        #expect(r.metRequests == 20)
        #expect(r.noaaBatchCalls <= 2)
        // Sharing tiles: far fewer NOAA requests than twenty separate places would cost (20 x (12 + 48) = 1200).
        #expect(r.noaaRequests < 20 * 12)
        #expect(r.firstScore < r.complete)
    }

    @Test func sixStopTripAcross500Km() async {
        // Six stops about 90 km apart (a degree of latitude is 111 km), two a day over three days.
        let stops = (0..<6).map { i in makePlace("S\(i)", lat: 36.0 + Double(i) * 0.9, lon: -105.0 + Double(i) * 0.4) }
        let first = localDay(of: stops[0])
        let r = await run("6-stop trip, 500 km") { _ in
            stops.enumerated().map { i, p in ConditionsRequest(place: p, day: first.adding(days: i / 2), priority: i == 0 ? .activeTrip : .pinnedTrip) }
        }
        print(line(r))
        #expect(r.completeReports == 6)
        #expect(r.metRequests == 6)
        #expect(r.firstScore < r.complete)
    }
}
