import Foundation
import Synchronization
import Testing
import IterModel
import IterSources
import IterSourcesLive

private let now = NOMADSTest.at(14, 17)
private let twelveHours = TimeSpan(start: NOMADSTest.at(14), end: NOMADSTest.at(2, days: 1))

// Lone Pine and spots around it: one HRRR tile (36..37 N, -119..-118 E); the last is the next tile north.
private let lonePine = Coordinate(latitude: 36.6, longitude: -118.06)
private let nearby = [Coordinate(latitude: 36.5785, longitude: -118.2923), Coordinate(latitude: 36.35, longitude: -118.1),
                      Coordinate(latitude: 36.95, longitude: -118.8)]
private let farNorth = Coordinate(latitude: 37.4, longitude: -118.4)
private let zurich = Coordinate(latitude: 47.37, longitude: 8.54)

private func provider(_ http: any HTTPClient, cache: (any BlobCaching)? = nil) -> NOMADSForecastProvider {
    NOMADSForecastProvider(http: http, clock: ManualSourceClock(now: now), cache: cache)
}

@Suite struct NOMADSBatchTests {
    @Test func spotsInOneTileShareEveryDownload() async throws {
        let client = SyntheticNOMADSClient()
        let coords = [lonePine] + nearby
        let results = await provider(client).forecasts(at: coords, span: twelveHours)
        #expect(results.count == 4)
        // One tile, 13 hours: 13 requests for four points (the old per-cell geometry took 3 tiles x 13).
        #expect(client.requests.count == 13)
        for c in coords {
            let r = try #require(try? results[c]?.get(), "\(c)")
            #expect(r.value.hours.count == 13)
            // The synthetic files carry the forecast hour as the temperature: 13Z f01 ... f13 at 14:00 ... 02:00.
            #expect(r.value.hours.enumerated().allSatisfy { i, h in abs((h.tempC ?? -99) - Double(i + 1)) < 0.01 })
            #expect(r.provenance.model == "HRRR 2026-11-22 13Z f01–f13")
        }
    }

    @Test func eachTileIsFetchedOncePerHourAndTheResultMatchesASingleCall() async throws {
        let client = SyntheticNOMADSClient()
        let coords = [lonePine, farNorth]
        let results = await provider(client).forecasts(at: coords, span: twelveHours)
        #expect(client.requests.count == 2 * 13)
        let urls = client.requests.map(\.url)
        #expect(Set(urls).count == urls.count, "no file twice")
        let boxes = Set(client.parsed.map(\.box.id))
        #expect(boxes == ["35.9,-119.1,37.1,-117.9", "36.9,-119.1,38.1,-117.9"])
        for c in coords {
            let single = try await provider(SyntheticNOMADSClient()).forecast(at: c, span: twelveHours)
            let batch = try #require(try? results[c]?.get())
            #expect(batch.value == single.value)
        }
    }

    @Test func duplicateCoordinatesAreOneEntryAndEmptyInputIsEmpty() async throws {
        let client = SyntheticNOMADSClient()
        let results = await provider(client).forecasts(at: [lonePine, lonePine, lonePine], span: twelveHours)
        #expect(results.count == 1 && client.requests.count == 13)
        let none = await provider(client).forecasts(at: [], span: twelveHours)
        #expect(none.isEmpty && client.requests.count == 13)
    }

    @Test func pointsOutsideHRRRDropToGFSAndShareItsTile() async throws {
        let client = SyntheticNOMADSClient()
        let results = await provider(client).forecasts(at: [lonePine, zurich, Coordinate(latitude: 46.9, longitude: 9.1)], span: twelveHours)
        let us = try #require(try? results[lonePine]?.get())
        let eu = try #require(try? results[zurich]?.get())
        #expect(us.provenance.model == "HRRR 2026-11-22 13Z f01–f13")
        #expect(eu.provenance.model == "GFS 2026-11-22 06Z f008–f020")
        #expect(eu.value.hours.allSatisfy { $0.smokeUgm3 == nil })
        let other = try #require(try? results[Coordinate(latitude: 46.9, longitude: 9.1)]?.get())
        #expect(other.value.hours.count == 13)
        // 13 HRRR files for the US tile, 13 GFS files for the one GFS tile both European points share.
        let parsed = client.parsed
        #expect(parsed.filter { $0.ref.model == .hrrr }.count == 13 && parsed.filter { $0.ref.model == .gfs }.count == 13)
    }

    @Test func nearHoursOfEveryTileComeBeforeLaterHours() async throws {
        let client = SyntheticNOMADSClient()
        let coords = [lonePine, farNorth, Coordinate(latitude: 38.5, longitude: -118.5), Coordinate(latitude: 35.5, longitude: -118.5)]
        _ = await provider(client).forecasts(at: coords, span: twelveHours)
        let hours = client.parsed.map(\.ref.forecastHour)
        #expect(hours.count == 4 * 13)
        // The first eight requests (probe, then two hours of four tiles) never reach past f03 (two in flight may swap).
        #expect(hours.prefix(8).allSatisfy { $0 <= 3 })
        #expect(hours.suffix(8).allSatisfy { $0 >= 12 })
        // Each tile's own hours go in order.
        for box in Set(client.parsed.map(\.box.id)) {
            let own = client.parsed.filter { $0.box.id == box }.map(\.ref.forecastHour)
            #expect(own.count == 13)
            #expect(zip(own, own.dropFirst()).allSatisfy { $0 <= $1 + 1 })
        }
    }

    @Test func aLongerSecondCallDoesNotRefetchTheFirstCallsHours() async throws {
        let client = SyntheticNOMADSClient()
        let cache = InMemoryBlobCache(clock: ManualSourceClock(now: now))
        let p = provider(client, cache: cache)
        let coords = [lonePine, farNorth]
        // First the next 12 hours, later two days.
        let first = await p.forecasts(at: coords, span: twelveHours)
        #expect(first.values.allSatisfy { (try? $0.get().value.hours.count) == 13 })
        let firstURLs = Set(client.requests.map(\.url))
        #expect(firstURLs.count == 26)
        let long = TimeSpan(start: NOMADSTest.at(14), end: NOMADSTest.at(14, days: 2))
        let second = await p.forecasts(at: coords, span: long)
        let plan = NOMADSCyclePlanner.plan(span: long, now: now)
        let newRequests = client.requests.dropFirst(26)
        // Only the hours the first call lacked: 2 HRRR tiles per HRRR hour, and the one GFS tile both points share per GFS hour.
        let fresh = plan.hours.dropFirst(13)
        let expected = fresh.filter { $0.primary?.model == .hrrr }.count * 2 + fresh.filter { $0.primary?.model == .gfs }.count * 1
        #expect(newRequests.count == expected && expected > 60, "\(newRequests.count) vs \(expected)")
        #expect(newRequests.allSatisfy { !firstURLs.contains($0.url) })
        for c in coords {
            let r = try #require(try? second[c]?.get())
            #expect(r.value.hours.count == plan.hours.count)
        }
    }

    @Test func cancellingStopsTheRemainingFetchesAndKeepsTheNearHoursCached() async throws {
        let handle = Mutex<Task<[Coordinate: Result<Sourced<HourlySeries>, SourceError>], Never>?>(nil)
        let client = SyntheticNOMADSClient(onRequest: { n in if n == 6 { handle.withLock { $0?.cancel() } } })
        let cache = InMemoryBlobCache(clock: ManualSourceClock(now: now))
        let p = provider(client, cache: cache)
        let coords = [lonePine, farNorth]
        let long = TimeSpan(start: NOMADSTest.at(14), end: NOMADSTest.at(14, days: 2))
        let task = Task { await p.forecasts(at: coords, span: long) }
        handle.withLock { $0 = task }
        let results = await task.value
        // Cancelled at the 6th request: at most the two in flight finish, nothing more starts.
        #expect(client.requests.count >= 6 && client.requests.count <= 6 + 3, "\(client.requests.count)")
        for c in coords { #expect(results[c].map { if case .failure(.cancelled) = $0 { true } else { false } } == true) }
        // What arrived is the near hours of both tiles.
        #expect(client.parsed.map(\.ref.forecastHour).allSatisfy { $0 <= 4 })
        #expect(cache.count >= 5)
        // A new call finds those hours cached and asks only for what is missing.
        let before = client.requests.count, cached = cache.count
        let again = await provider(client, cache: cache).forecasts(at: coords, span: twelveHours)
        #expect(again.values.allSatisfy { (try? $0.get()) != nil })
        #expect(client.requests.count - before == 26 - cached)
    }

    @Test func identicalConcurrentCallsShareOneDownload() async throws {
        let client = SyntheticNOMADSClient()
        client.hold()
        let p = provider(client)
        let hour = TimeSpan(start: NOMADSTest.at(14), end: NOMADSTest.at(14))
        async let a = p.forecasts(at: [lonePine], span: hour)
        async let b = p.forecasts(at: [nearby[0]], span: hour)
        // Both are waiting for the same file; wait until the first request is out and the second has had time to join it.
        while client.requests.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        try await Task.sleep(for: .milliseconds(300))
        client.release()
        let (ra, rb) = await (a, b)
        #expect(client.requests.count == 1, "\(client.requests.count)")
        #expect((try? ra[lonePine]?.get()) != nil && (try? rb[nearby[0]]?.get()) != nil)
    }

    @Test func hoursNotPostedForOneTileAreNotPostedForTheOthersEither() async throws {
        // HRRR 13Z is posted to f05 only: the first miss is remembered for the cycle, so the other tile does not repeat it,
        // and both points get HRRR for 14:00...18:00 and GFS for the rest.
        let client = SyntheticNOMADSClient(missing: { $0.ref.model == .hrrr && $0.ref.cycleHourUTC == 13 && $0.ref.forecastHour > 5 })
        let results = await provider(client).forecasts(at: [lonePine, farNorth], span: twelveHours)
        for c in [lonePine, farNorth] {
            let r = try #require(try? results[c]?.get())
            #expect(r.value.hours.count == 13)
            #expect(r.value.hours.prefix(5).allSatisfy { $0.smokeUgm3 != nil })
        }
        let misses = client.parsed.filter { $0.ref.model == .hrrr && $0.ref.cycleHourUTC == 13 && $0.ref.forecastHour > 5 }
        #expect(misses.count <= 2 + 2, "\(misses.count) wasted requests")
    }

    @Test func spanTooOldFailsEveryPoint() async throws {
        let client = SyntheticNOMADSClient()
        let old = TimeSpan(start: NOMADSTest.at(0, days: -9), end: NOMADSTest.at(6, days: -9))
        let results = await provider(client).forecasts(at: [lonePine, farNorth], span: old)
        for c in [lonePine, farNorth] {
            guard case .failure(.invalidRequest)? = results[c] else { Issue.record("\(c)"); continue }
        }
        #expect(client.requests.isEmpty)
    }

    @Test func offlineFailsEveryPointWithOffline() async throws {
        let http = StubHTTPClient()
        http.on(urlContaining: "nomads.ncep.noaa.gov", reply: .error(.offline))
        let results = await provider(http).forecasts(at: [lonePine, farNorth], span: twelveHours)
        for c in [lonePine, farNorth] {
            guard case .failure(.offline)? = results[c] else { Issue.record("\(c)"); continue }
        }
        #expect(http.requests.count <= 1 + 2)
    }
}

@Suite struct HRRRSmokeBatchTests {
    @Test func smokeBatchSharesTilesAndReportsOutsideCoverage() async throws {
        let client = SyntheticNOMADSClient()
        let smoke = HRRRSmokeProvider(http: client, clock: ManualSourceClock(now: now))
        let results = await smoke.forecasts(at: [lonePine, nearby[0], farNorth, zurich], span: twelveHours)
        #expect(results.count == 4)
        #expect(client.requests.count == 2 * 13)
        #expect(client.parsed.allSatisfy { $0.ref.model == .hrrr })
        for c in [lonePine, nearby[0], farNorth] {
            let r = try #require(try? results[c]?.get(), "\(c)")
            #expect(r.value.hours.count == 13)
            #expect(r.value.hours.allSatisfy { Set($0.presentFields) == [.smokeUgm3] && abs(($0.smokeUgm3 ?? 0) - 20) < 0.01 })
            #expect(r.provenance.source == .noaaHRRRSmoke)
        }
        guard case .failure(.outsideCoverage)? = results[zurich] else { Issue.record("zurich"); return }
    }

    @Test func smokeAndForecastShareFilesThroughOneProvider() async throws {
        let client = SyntheticNOMADSClient()
        let cache = InMemoryBlobCache(clock: ManualSourceClock(now: now))
        let forecast = provider(client, cache: cache)
        _ = await forecast.forecasts(at: [lonePine, farNorth], span: twelveHours)
        #expect(client.requests.count == 26)
        let smoke = HRRRSmokeProvider(sharing: forecast)
        let r = await smoke.forecasts(at: [lonePine, farNorth], span: twelveHours)
        #expect(client.requests.count == 26 && r.count == 2)
    }
}
