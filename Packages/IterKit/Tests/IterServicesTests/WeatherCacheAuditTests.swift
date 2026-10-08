import Testing
import Foundation
import Synchronization
import IterCore
@testable import IterServices

private func stamp(_ hour: Int, _ minute: Int = 0, _ second: Int = 0) -> Date {
    Date(timeIntervalSince1970: 1_595_246_400 - 12 * 3600 + Double(hour * 3600 + minute * 60 + second))   // 2020-07-20 00:00 UTC + h:m:s
}

private func forecast(at date: Date, _ c: Coordinate = moabSpot) -> Forecast {
    Forecast(coordinate: c, hours: [], days: [], fetchedAt: date, source: .openWeather)
}

/// Counts fetches; every fetch answers with a forecast stamped by the clock.
private final class Fetches: Sendable {
    private let n = Mutex(0)
    var count: Int { n.withLock { $0 } }
    func make(_ clock: TestClock, _ c: Coordinate = moabSpot) -> @Sendable () async throws -> Forecast {
        { [self] in n.withLock { $0 += 1 }; return forecast(at: clock.now, c) }
    }
}

@Suite("Provider cache boundaries") struct ProviderCacheBoundaryTests {
    @Test("through the next clock hour: fetched at the start, middle or end of hour 12, served until 14:00 UTC and not after",
          arguments: [(12, 0, 0), (12, 30, 0), (12, 59, 59)])
    func throughNextClockHour(_ h: Int, _ m: Int, _ s: Int) async throws {
        let clock = TestClock(stamp(h, m, s)), fetches = Fetches()
        let cache = ProviderCache(directory: nil, validity: .throughNextClockHour, now: { clock.now })
        _ = try await cache.forecast(for: moabSpot, fetch: fetches.make(clock))
        clock.set(stamp(13, 59, 59))
        _ = try await cache.forecast(for: moabSpot, fetch: fetches.make(clock))
        #expect(fetches.count == 1)
        clock.set(stamp(14))
        _ = try await cache.forecast(for: moabSpot, fetch: fetches.make(clock))
        #expect(fetches.count == 2)
    }

    @Test func intervalCacheEndsExactlyAtItsTimeToLive() async throws {
        let clock = TestClock(stamp(12, 20)), fetches = Fetches()
        let cache = ProviderCache(directory: nil, validity: .interval(3 * 3600), now: { clock.now })
        _ = try await cache.forecast(for: moabSpot, fetch: fetches.make(clock))
        clock.set(stamp(15, 19, 59))
        _ = try await cache.forecast(for: moabSpot, fetch: fetches.make(clock))
        #expect(fetches.count == 1)
        clock.set(stamp(15, 20))
        _ = try await cache.forecast(for: moabSpot, fetch: fetches.make(clock))
        #expect(fetches.count == 2)
    }

    @Test func twoSpotsInOneCellShareAFetchAndTheNextCellDoesNot() async throws {
        let clock = TestClock(stamp(12)), fetches = Fetches()
        let cache = ProviderCache(directory: nil, validity: .throughNextClockHour, now: { clock.now })
        let a = Coordinate(latitude: 38.571, longitude: -109.552), b = Coordinate(latitude: 38.574, longitude: -109.548)
        let c = Coordinate(latitude: 38.586, longitude: -109.548)
        _ = try await cache.forecast(for: a, fetch: fetches.make(clock, a))
        _ = try await cache.forecast(for: b, fetch: fetches.make(clock, b))
        #expect(fetches.count == 1)
        _ = try await cache.forecast(for: c, fetch: fetches.make(clock, c))
        #expect(fetches.count == 2)
    }

    @Test func aDiskFileNamedForThisHourButFetchedLongAgoIsNotServed() async throws {
        // A file's name says when it was fetched, its content says when too; the content decides, so a stale
        // forecast copied or renamed into the current hour's slot can never outlive the rule.
        let dir = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let clock = TestClock(stamp(12, 10)), fetches = Fetches()
        let old = forecast(at: stamp(7))
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = "\(String(format: "%.2f_%.2f", moabSpot.latitude, moabSpot.longitude))@\(ProviderCache.bucket(of: clock.now)).json"
        try JSONEncoder().encode(old).write(to: dir.appendingPathComponent(name))
        let cache = ProviderCache(directory: dir, validity: .throughNextClockHour, now: { clock.now })
        #expect(await cache.cached(for: moabSpot) == nil)
        _ = try await cache.forecast(for: moabSpot, fetch: fetches.make(clock))
        #expect(fetches.count == 1)
    }

    @Test func corruptOrEmptyDiskFilesAreMissesAndGetOverwritten() async throws {
        let dir = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let clock = TestClock(stamp(12, 10)), fetches = Fetches()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let bucket = ProviderCache.bucket(of: clock.now)
        for b in [bucket, bucket - 1] {
            try Data("{ not json".utf8).write(to: dir.appendingPathComponent("38.57_-109.55@\(b).json"))
        }
        try Data().write(to: dir.appendingPathComponent("garbage.json"))
        let cache = ProviderCache(directory: dir, validity: .throughNextClockHour, now: { clock.now })
        _ = try await cache.forecast(for: moabSpot, fetch: fetches.make(clock))
        #expect(fetches.count == 1)
        let reborn = ProviderCache(directory: dir, validity: .throughNextClockHour, now: { clock.now })
        #expect(await reborn.cached(for: moabSpot) != nil)   // the corrupt file was replaced by a good one
    }

    @Test func anUnreadableDirectoryStillGivesAWorkingMemoryCache() async throws {
        let blocker = scratchDirectory()          // a plain file where the directory should be
        try Data().write(to: blocker)
        defer { try? FileManager.default.removeItem(at: blocker) }
        let clock = TestClock(stamp(12, 10)), fetches = Fetches()
        let cache = ProviderCache(directory: blocker.appendingPathComponent("sub"), validity: .throughNextClockHour, now: { clock.now })
        _ = try await cache.forecast(for: moabSpot, fetch: fetches.make(clock))
        _ = try await cache.forecast(for: moabSpot, fetch: fetches.make(clock))
        #expect(fetches.count == 1)
    }

    @Test func aClockSetBackDoesNotServeAForecastFromTheFuture() async throws {
        let clock = TestClock(stamp(12, 10)), fetches = Fetches()
        let cache = ProviderCache(directory: nil, validity: .throughNextClockHour, now: { clock.now })
        _ = try await cache.forecast(for: moabSpot, fetch: fetches.make(clock))
        clock.set(stamp(11, 0))
        _ = try await cache.forecast(for: moabSpot, fetch: fetches.make(clock))
        #expect(fetches.count == 2)
    }

    @Test func aFailedSharedFetchReachesEveryWaiterAndIsNotCached() async throws {
        let clock = TestClock(stamp(12)), calls = Mutex(0)
        let cache = ProviderCache(directory: nil, validity: .throughNextClockHour, now: { clock.now })
        let failing: @Sendable () async throws -> Forecast = {
            calls.withLock { $0 += 1 }
            try await Task.sleep(for: .milliseconds(50))
            throw WeatherError.offline(.openWeather)
        }
        await withTaskGroup(of: Bool.self) { g in
            for _ in 0..<4 { g.addTask { (try? await cache.forecast(for: moabSpot, fetch: failing)) == nil } }
            for await failed in g { #expect(failed) }
        }
        #expect(calls.withLock { $0 } == 1)
        let fetches = Fetches()
        _ = try await cache.forecast(for: moabSpot, fetch: fetches.make(clock))
        #expect(fetches.count == 1)
    }

    @Test func aCancelledCallerDoesNotCancelTheFetchTheOthersWaitOn() async throws {
        let clock = TestClock(stamp(12)), fetches = Fetches()
        let cache = ProviderCache(directory: nil, validity: .throughNextClockHour, now: { clock.now })
        let slow: @Sendable () async throws -> Forecast = {
            try await Task.sleep(for: .milliseconds(80))
            return forecast(at: clock.now)
        }
        let first = Task { try await cache.forecast(for: moabSpot, fetch: slow) }
        try await Task.sleep(for: .milliseconds(10))
        let second = Task { try await cache.forecast(for: moabSpot, fetch: fetches.make(clock)) }
        first.cancel()
        _ = try await second.value
        #expect(fetches.count == 0)    // the second joined the first fetch instead of starting its own
    }
}

@Suite("Call budget audit") struct CallBudgetAuditTests {
    @Test func rolloverIsExactlyAtUTCMidnightAndIgnoresTheLocalZone() throws {
        let clock = TestClock(Date(timeIntervalSince1970: 1_595_289_600 - 1))   // 2020-07-20 23:59:59 UTC
        let b = CallBudget(defaults: scratchDefaults(), caps: [.openWeather: 2], now: { clock.now })
        try b.reserve(.openWeather); try b.reserve(.openWeather)
        #expect(b.callsToday(for: .openWeather) == 2)
        clock.advance(1)
        #expect(b.callsToday(for: .openWeather) == 0)
        try b.reserve(.openWeather)
        #expect(b.callsToday(for: .openWeather) == 1)
    }

    @Test func aZeroCapRefusesEveryCallAndCountsNothing() {
        let b = CallBudget(defaults: scratchDefaults(), caps: [.windy: 0])
        #expect(throws: WeatherError.overDailyLimit(.windy)) { try b.reserve(.windy) }
        #expect(b.callsToday(for: .windy) == 0)
    }

    @Test func parallelReservationsNeverPassTheCap() async {
        let b = CallBudget(defaults: scratchDefaults(), caps: [.openWeather: 25])
        let granted = await withTaskGroup(of: Bool.self) { g in
            for _ in 0..<100 { g.addTask { (try? b.reserve(.openWeather)) != nil } }
            return await g.reduce(0) { $0 + ($1 ? 1 : 0) }
        }
        #expect(granted == 25 && b.callsToday(for: .openWeather) == 25)
    }

    @Test func cacheHitsAndJoinedCallsSpendNoBudget() async throws {
        let rig = Rig(transport: FakeTransport { _ in (200, WeatherFixture.data("openweather-onecall3-documented.json")) }, caps: [.openWeather: 1])
        let s = rig.openWeather()
        await withTaskGroup(of: Void.self) { g in
            for _ in 0..<8 { g.addTask { _ = try? await s.forecast(for: moabSpot) } }
        }
        _ = try await s.forecast(for: moabSpot)
        #expect(rig.budget.callsToday(for: .openWeather) == 1 && rig.transport.callCount == 1)
    }
}
