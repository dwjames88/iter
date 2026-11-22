import Foundation
import Testing
import IterModel
import IterSources
import IterSourcesLive

private let W = Coordinate(latitude: 36.5785, longitude: -118.2923)
private let S = Coordinate(latitude: 46.5586, longitude: 8.5610)

/// A stub NOMADS: routes on the `file=` parameter. Posted files are real fixtures retargeted to the cycle and hour in the
/// request; every other file answers 404 with the recorded "Data file is not present" page.
private struct StubNOMADS {
    let http = StubHTTPClient()
    private let hrrrBase: Data
    private let gfsBaseW: Data
    private let gfsBaseS: Data
    let notPresent: Data

    init() throws {
        hrrrBase = try GRIB2Fixtures.data("hrrr-W-20261122t12z-f01")
        gfsBaseW = try GRIB2Fixtures.data("gfs-W-20261122t06z-f003")
        gfsBaseS = try GRIB2Fixtures.data("gfs-S-20261122t06z-f003")
        notPresent = try Fixtures.data("NOMADS/hrrr-cycle-running.html")
    }

    /// Serves HRRR files `hours` of `cycle`.
    func postHRRR(cycle: Date, hours: ClosedRange<Int>) { postHRRR(cycle: cycle, hours: Array(hours)) }

    func postHRRR(cycle: Date, hours: [Int]) {
        let hh = String(format: "%02d", NOMADSFileRef(model: .hrrr, cycle: cycle, forecastHour: 1).cycleHourUTC)
        for fh in hours {
            let body = GRIBRetarget.make(hrrrBase, cycle: cycle, forecastHour: fh)
            let dir = NOMADSFileRef(model: .hrrr, cycle: cycle, forecastHour: 1).dateStamp
            http.on(urlContaining: "dir=%2Fhrrr.\(dir)%2Fconus&file=hrrr.t\(hh)z.wrfsfcf\(String(format: "%02d", fh)).grib2&", reply: .ok(body))
        }
    }

    /// Serves GFS files for `hours` of `cycle`, for the W or S fixture box.
    func postGFS(cycle: Date, hours: [Int], south: Bool = false) {
        let hh = String(format: "%02d", NOMADSFileRef(model: .gfs, cycle: cycle, forecastHour: 1).cycleHourUTC)
        for fh in hours {
            let body = GRIBRetarget.make(south ? gfsBaseS : gfsBaseW, cycle: cycle, forecastHour: fh)
            let dir = NOMADSFileRef(model: .gfs, cycle: cycle, forecastHour: 1).dateStamp
            http.on(urlContaining: "dir=%2Fgfs.\(dir)%2F\(hh)%2Fatmos&file=gfs.t\(hh)z.pgrb2.0p25.f\(String(format: "%03d", fh))&", reply: .ok(body))
        }
    }

    /// Everything else: 404 "not present". Call last.
    func finish() { http.on(urlContaining: "nomads.ncep.noaa.gov", reply: .status(404, notPresent)) }
}

private func provider(_ stub: StubNOMADS, now: Date, cache: (any BlobCaching)? = nil) -> NOMADSForecastProvider {
    NOMADSForecastProvider(http: stub.http, clock: ManualSourceClock(now: now), cache: cache)
}

@Suite struct NOMADSProviderTests {
    private let now = NOMADSTest.at(14, 17)
    private var twelveHours: TimeSpan { TimeSpan(start: NOMADSTest.at(14), end: NOMADSTest.at(2, days: 1)) }

    // MARK: Request count and shape

    @Test func twelveHourSpanAtWMakesThirteenHRRRRequests() async throws {
        let stub = try StubNOMADS()
        stub.postHRRR(cycle: NOMADSTest.at(13), hours: 1...18)
        stub.finish()
        let result = try await provider(stub, now: now).forecast(at: W, span: twelveHours)
        let requests = stub.http.requests
        #expect(requests.count == 13)
        for r in requests {
            let url = r.url.absoluteString
            #expect(url.hasPrefix("https://nomads.ncep.noaa.gov/cgi-bin/filter_hrrr_2d.pl?"))
            #expect(NOMADSTest.query(r, "dir") == "/hrrr.20261122/conus")
            #expect(NOMADSTest.query(r, "toplat") == "37" && NOMADSTest.query(r, "bottomlat") == "36.25")
            #expect(NOMADSTest.query(r, "leftlon") == "-118.75" && NOMADSTest.query(r, "rightlon") == "-118")
            #expect(url.contains("var_MASSDEN=on") && url.contains("var_AOTK=on") && url.contains("subregion=&"))
            #expect(r.source == .noaaNOMADS)
            #expect(r.headers["User-Agent"] == nil, "SourceHTTP sets the User-Agent, adapters do not")
        }
        let files = Set(requests.map { NOMADSTest.file($0) })
        #expect(files == Set((1...13).map { "hrrr.t13z.wrfsfcf\(String(format: "%02d", $0)).grib2" }))
        // The series: 13 hourly rows at the native valid times 14:00 ... 02:00.
        let hours = result.value.hours
        #expect(hours.count == 13)
        #expect(hours.map(\.time) == (0..<13).map { NOMADSTest.at(14).addingTimeInterval(TimeInterval($0) * 3600) })
        #expect(result.provenance.model == "HRRR 2026-11-22 13Z f01–f13")
        #expect(result.provenance.issuedAt == NOMADSTest.at(13))
        #expect(result.provenance.validFor == twelveHours)
        #expect(result.provenance.url?.absoluteString == "https://nomads.ncep.noaa.gov/")
        #expect(result.provenance.source == .noaaNOMADS)
        #expect((result.provenance.distanceKm ?? 99) < 3)
        #expect(result.provenance.licence.mayStore)
    }

    @Test func requestCountsForTypicalSpans() async throws {
        // Every file posted, so no fallbacks: the count is the plan size.
        func count(_ hours: Double, at c: Coordinate) async throws -> (requests: Int, rows: Int) {
            let stub = try StubNOMADS()
            for h in 0...23 { stub.postHRRR(cycle: NOMADSTest.at(h, days: -1), hours: 1...(h % 6 == 0 ? 48 : 18)) }
            for h in 0...14 { stub.postHRRR(cycle: NOMADSTest.at(h), hours: 1...(h % 6 == 0 ? 48 : 18)) }
            for (cycle, _) in [(NOMADSTest.at(6), 0), (NOMADSTest.at(0), 0), (NOMADSTest.at(18, days: -1), 0)] {
                stub.postGFS(cycle: cycle, hours: Array(1...120) + stride(from: 123, through: 384, by: 3).map { $0 }, south: c == S)
            }
            stub.finish()
            let r = try await provider(stub, now: now).forecast(at: c, span: TimeSpan(start: now, end: now.addingTimeInterval(hours * 3600)))
            return (stub.http.requests.count, r.value.hours.count)
        }
        let us12 = try await count(12, at: W), us48 = try await count(48, at: W), us240 = try await count(240, at: W)
        let eu12 = try await count(12, at: S), eu48 = try await count(48, at: S), eu240 = try await count(240, at: S)
        print("NOMADS requests: US 12 h \(us12.requests), 48 h \(us48.requests), 10 d \(us240.requests); non-US 12 h \(eu12.requests), 48 h \(eu48.requests), 10 d \(eu240.requests)")
        #expect(us12.requests == 14 && us12.rows == 14)
        #expect(us48.requests == 50 && us48.rows == 50)
        #expect(us240.requests == 82 && us240.rows == 82)
        #expect(eu12.requests == 14 && eu48.requests == 50 && eu240.requests == 82)
    }

    @Test func pointOutsideHRRRUsesGFSOnly() async throws {
        let stub = try StubNOMADS()
        stub.postGFS(cycle: NOMADSTest.at(6), hours: Array(8...20), south: true)
        stub.finish()
        let result = try await provider(stub, now: now).forecast(at: S, span: twelveHours)
        let requests = stub.http.requests
        #expect(requests.count == 13)
        for r in requests {
            #expect(r.url.absoluteString.hasPrefix("https://nomads.ncep.noaa.gov/cgi-bin/filter_gfs_0p25.pl?"))
            #expect(NOMADSTest.query(r, "dir") == "/gfs.20261122/06/atmos")
            #expect(NOMADSTest.query(r, "toplat") == "47.5" && NOMADSTest.query(r, "bottomlat") == "46")
            #expect(NOMADSTest.query(r, "leftlon") == "8" && NOMADSTest.query(r, "rightlon") == "9.5")
            #expect(!r.url.absoluteString.contains("MASSDEN"))
        }
        #expect(Set(requests.map { NOMADSTest.file($0) }) == Set((8...20).map { "gfs.t06z.pgrb2.0p25.f\(String(format: "%03d", $0))" }))
        #expect(result.value.hours.count == 13)
        #expect(result.provenance.model == "GFS 2026-11-22 06Z f008–f020")
        #expect(result.value.hours.allSatisfy { $0.smokeUgm3 == nil && $0.aod550 == nil })
        #expect(result.value.fieldSources[.smokeUgm3] == nil)
        // GFS rows read at S: precipitation from PRATE, cloud from the instantaneous messages.
        #expect(result.value.hours.allSatisfy { $0.precipMm != nil && $0.cloudLow != nil })
        #expect((result.provenance.distanceKm ?? 0) > 0)
    }

    // MARK: Cycle fallback

    @Test func unpostedCycleFallsBackToThePreviousOne() async throws {
        let stub = try StubNOMADS()
        // 13Z f01 "is due" at 14:17 but is still running; the 12Z cycle is complete.
        stub.postHRRR(cycle: NOMADSTest.at(12), hours: 1...48)
        stub.finish()
        let p = provider(stub, now: now)
        let result = try await p.forecast(at: W, span: twelveHours)
        let requests = stub.http.requests
        // One probe of 13Z f01 that 404s, then 13 hours from 12Z (f02 ... f14).
        #expect(requests.count == 14)
        #expect(NOMADSTest.file(requests[0]) == "hrrr.t13z.wrfsfcf01.grib2")
        let rest = requests.dropFirst().map { NOMADSTest.file($0) }
        #expect(Set(rest) == Set((2...14).map { "hrrr.t12z.wrfsfcf\(String(format: "%02d", $0)).grib2" }))
        #expect(result.value.hours.count == 13)
        #expect(result.provenance.model == "HRRR 2026-11-22 12Z f02–f14")
        #expect(result.provenance.issuedAt == NOMADSTest.at(12))
        #expect(await p.lastGoodCycle(.hrrr) == NOMADSTest.at(12))
        #expect(await p.lastGoodCycle(.gfs) == nil)
        // A second call inside five minutes does not probe 13Z again (and the 12Z boxes are cached only with a cache).
        let before = stub.http.requests.count
        _ = try await p.forecast(at: W, span: twelveHours)
        #expect(stub.http.requests.dropFirst(before).allSatisfy { NOMADSTest.file($0).hasPrefix("hrrr.t12z") })
    }

    @Test func missingLaterHourIsTakenFromAnotherCycleOrGFS() async throws {
        let stub = try StubNOMADS()
        // 13Z is posted to f18, but the plan only expects it to f16 at 14:17 (f17 and f18 are due at 14:18 and 14:20), so the
        // last hours are planned from the 12Z synoptic run (f18 and later), which the stub does not have. Its fallbacks
        // (06Z f24, 00Z f30) are missing too, and GFS 06Z supplies the rest.
        stub.postHRRR(cycle: NOMADSTest.at(13), hours: 1...18)
        stub.postGFS(cycle: NOMADSTest.at(6), hours: Array(1...120))
        stub.finish()
        let span = TimeSpan(start: NOMADSTest.at(14), end: NOMADSTest.at(9, days: 1))
        let result = try await provider(stub, now: now).forecast(at: W, span: span)
        let hours = result.value.hours
        #expect(hours.count == 20)  // 14:00 ... 09:00 next day
        // HRRR f01...f16 cover 14:00...05:00, GFS 06Z f024...f027 the last four hours.
        #expect(hours.prefix(16).allSatisfy { $0.smokeUgm3 != nil && $0.aod550 != nil })
        #expect(hours.suffix(4).allSatisfy { $0.smokeUgm3 == nil && $0.cloudTotal != nil })
        #expect(result.provenance.model == "HRRR 2026-11-22 13Z f01–f16; GFS 2026-11-22 06Z f024–f027")
        #expect(result.provenance.issuedAt == NOMADSTest.at(13))
        #expect(hours.map(\.time) == hours.map(\.time).sorted() && Set(hours.map(\.time)).count == hours.count)
        // Never more than a handful of wasted probes.
        #expect(stub.http.requests.count <= 20 + 8, "\(stub.http.requests.count) requests")
    }

    @Test func stitchedSeriesNamesTheSourceOfEveryPresentField() async throws {
        let stub = try StubNOMADS()
        stub.postHRRR(cycle: NOMADSTest.at(13), hours: 1...18)
        stub.postGFS(cycle: NOMADSTest.at(6), hours: [24, 25, 26, 27])
        stub.finish()
        let span = TimeSpan(start: NOMADSTest.at(14), end: NOMADSTest.at(9, days: 1))
        let result = try await provider(stub, now: now).forecast(at: W, span: span)
        let present = Set(result.value.hours.flatMap(\.presentFields))
        #expect(!present.isEmpty)
        for field in HourlyField.allCases {
            if present.contains(field) { #expect(result.value.fieldSources[field] == .noaaNOMADS, "\(field)") }
            else { #expect(result.value.fieldSources[field] == nil, "\(field)") }
        }
        for f in [HourlyField.cloudTotal, .cloudLow, .cloudMid, .cloudHigh, .visibilityKm, .tempC, .dewpointC, .rhPercent,
                  .windMs, .gustMs, .windDirDeg, .precipMm, .smokeUgm3, .aod550] {
            #expect(present.contains(f), "\(f)")
        }
        #expect(!present.contains(.precipChance) && !present.contains(.pm25) && !present.contains(.cloudBaseM))
    }

    // MARK: Cache

    @Test func secondIdenticalCallMakesNoRequests() async throws {
        let stub = try StubNOMADS()
        stub.postHRRR(cycle: NOMADSTest.at(13), hours: 1...18)
        stub.finish()
        let cache = InMemoryBlobCache(clock: ManualSourceClock(now: now))
        let p = provider(stub, now: now, cache: cache)
        let first = try await p.forecast(at: W, span: twelveHours)
        #expect(stub.http.requests.count == 13 && cache.count == 13)
        let second = try await p.forecast(at: W, span: twelveHours)
        #expect(stub.http.requests.count == 13)
        #expect(second.value == first.value)
        // A fresh provider with the same cache also makes none.
        let third = try await provider(stub, now: now, cache: cache).forecast(at: W, span: twelveHours)
        #expect(stub.http.requests.count == 13 && third.value == first.value)
    }

    @Test func overlappingSpansShareTheCachedBoxes() async throws {
        let stub = try StubNOMADS()
        stub.postHRRR(cycle: NOMADSTest.at(13), hours: 1...18)
        stub.finish()
        let cache = InMemoryBlobCache(clock: ManualSourceClock(now: now))
        let p = provider(stub, now: now, cache: cache)
        _ = try await p.forecast(at: W, span: TimeSpan(start: NOMADSTest.at(14), end: NOMADSTest.at(20)))  // 7 files
        #expect(stub.http.requests.count == 7)
        _ = try await p.forecast(at: W, span: TimeSpan(start: NOMADSTest.at(18), end: NOMADSTest.at(23)))  // 18...23: 4 are new
        #expect(stub.http.requests.count == 7 + 3)
        // A different point in the same HRRR cell shares the boxes; one in another cell does not.
        _ = try await p.forecast(at: Coordinate(latitude: 36.6, longitude: -118.3), span: TimeSpan(start: NOMADSTest.at(14), end: NOMADSTest.at(20)))
        #expect(stub.http.requests.count == 10)
        _ = try await p.forecast(at: Coordinate(latitude: 36.8, longitude: -118.3), span: TimeSpan(start: NOMADSTest.at(14), end: NOMADSTest.at(15)))
        #expect(stub.http.requests.count == 12)
    }

    @Test func cacheKeysAreRecordedPerBoxCycleAndHour() async throws {
        let stub = try StubNOMADS()
        stub.postHRRR(cycle: NOMADSTest.at(13), hours: 1...2)
        stub.finish()
        let cache = InMemoryBlobCache(clock: ManualSourceClock(now: now))
        _ = try await provider(stub, now: now, cache: cache).forecast(at: W, span: TimeSpan(start: NOMADSTest.at(14), end: NOMADSTest.at(15)))
        let key = CacheKey(source: .noaaNOMADS, kind: .forecast, cell: "36.25,-118.75,37,-118", bucket: "hrrr 2026112213 f001")
        let blob = await cache.blob(for: key, maxAge: nil)
        #expect(blob != nil)
        #expect(blob.map { Data($0.data.prefix(4)) } == Data("GRIB".utf8))
        #expect(cache.count == 2)
    }

    // MARK: Errors

    @Test func futureDataPageIsNotPublished() async throws {
        let stub = try StubNOMADS()
        let page = try Fixtures.data("NOMADS/hrrr-not-posted.html")
        stub.http.on(urlContaining: "nomads.ncep.noaa.gov", reply: .status(403, page))
        await #expect(throws: SourceError.self) { try await provider(stub, now: now).forecast(at: W, span: twelveHours) }
        do { _ = try await provider(stub, now: now).forecast(at: W, span: twelveHours); Issue.record("expected an error") } catch {
            guard case .notPublished = SourceError.wrap(error) else { Issue.record("wrong error \(error)"); return }
        }
    }

    @Test func nothingPostedAtAllIsNotPublishedAndBounded() async throws {
        let stub = try StubNOMADS()
        stub.finish()
        do { _ = try await provider(stub, now: now).forecast(at: W, span: twelveHours); Issue.record("expected an error") } catch {
            guard case .notPublished = SourceError.wrap(error) else { Issue.record("wrong error \(error)"); return }
        }
        // The first hour tries its six alternatives (3 HRRR, 3 GFS), and the misses it records shut those cycles for
        // later hours: far fewer than the 13 x 6 a naive loop would send.
        #expect(stub.http.requests.count <= 6 + 2 * 6, "\(stub.http.requests.count) requests")
    }

    @Test func aNonGRIBBodyWithStatus200IsADecodingError() async throws {
        let stub = try StubNOMADS()
        stub.http.on(urlContaining: "nomads.ncep.noaa.gov", reply: .ok(Data("<html>Missing variable</html>".utf8)))
        do { _ = try await provider(stub, now: now).forecast(at: W, span: twelveHours); Issue.record("expected an error") } catch {
            guard case .decoding = SourceError.wrap(error) else { Issue.record("wrong error \(error)"); return }
        }
    }

    @Test func aFileForTheWrongValidTimeIsRejected() async throws {
        let stub = try StubNOMADS()
        // 12Z f06 content served for every request.
        stub.http.on(urlContaining: "nomads.ncep.noaa.gov", reply: .ok(try GRIB2Fixtures.data("hrrr-W-20261122t12z-f06")))
        do {
            _ = try await provider(stub, now: now).forecast(at: W, span: TimeSpan(start: NOMADSTest.at(14), end: NOMADSTest.at(14)))
            Issue.record("expected an error")
        } catch { guard case .decoding = SourceError.wrap(error) else { Issue.record("wrong error \(error)"); return } }
    }

    @Test func offlineStopsTheRun() async throws {
        let stub = try StubNOMADS()
        stub.http.on(urlContaining: "nomads.ncep.noaa.gov", reply: .error(.offline))
        do { _ = try await provider(stub, now: now).forecast(at: W, span: twelveHours); Issue.record("expected an error") } catch {
            #expect(SourceError.wrap(error) == .offline)
        }
        #expect(stub.http.requests.count <= 1 + NOMADSProviderTests.maxInFlightSlack)
    }

    @Test func spanTooOldIsAnInvalidRequest() async throws {
        let stub = try StubNOMADS()
        stub.finish()
        do {
            _ = try await provider(stub, now: now).forecast(at: W, span: TimeSpan(start: NOMADSTest.at(0, days: -9), end: NOMADSTest.at(6, days: -9)))
            Issue.record("expected an error")
        } catch { guard case .invalidRequest = SourceError.wrap(error) else { Issue.record("wrong error \(error)"); return } }
        #expect(stub.http.requests.isEmpty)
    }

    static let maxInFlightSlack = 2

    // MARK: Partial results

    @Test func hoursThatCannotBeReadAreLeftOutNotInvented() async throws {
        let stub = try StubNOMADS()
        // 13Z has f01...f03 only; nothing else is posted, so 17:00 and 18:00 have no source at all.
        stub.postHRRR(cycle: NOMADSTest.at(13), hours: [1, 2, 3])
        stub.finish()
        let span = TimeSpan(start: NOMADSTest.at(14), end: NOMADSTest.at(18))
        let r = try await provider(stub, now: now).forecast(at: W, span: span)
        #expect(r.value.hours.map(\.time) == [14, 15, 16].map { NOMADSTest.at($0) })
        #expect(r.provenance.validFor == TimeSpan(start: NOMADSTest.at(14), end: NOMADSTest.at(16)))
        #expect(r.provenance.model == "HRRR 2026-11-22 13Z f01–f03")
    }

    // MARK: Nowcast

    @Test func nowcastIsTheNextSixHours() async throws {
        let stub = try StubNOMADS()
        stub.postHRRR(cycle: NOMADSTest.at(13), hours: 1...18)
        stub.finish()
        let r = try await provider(stub, now: now).nowcast(at: W)
        // 14:00 (the hour containing now) to 20:00.
        #expect(r.value.map(\.time) == (14...20).map { NOMADSTest.at($0) })
        #expect(stub.http.requests.count == 7)
        #expect(r.value.allSatisfy { $0.precipMmPerHour != nil && $0.cloudTotal != nil })
        #expect(r.provenance.model == "HRRR 2026-11-22 13Z f01–f07")
        #expect(r.provenance.source == .noaaNOMADS)
    }

    @Test func nowcastOutsideTheUSComesFromGFS() async throws {
        let stub = try StubNOMADS()
        stub.postGFS(cycle: NOMADSTest.at(6), hours: Array(8...14), south: true)
        stub.finish()
        let r = try await provider(stub, now: now).nowcast(at: S)
        #expect(r.value.count == 7)
        #expect(r.provenance.model == "GFS 2026-11-22 06Z f008–f014")
        #expect(stub.http.requests.allSatisfy { $0.url.absoluteString.contains("filter_gfs_0p25.pl") })
    }
}

@Suite struct HRRRSmokeProviderTests {
    private let now = NOMADSTest.at(14, 17)
    private let span = TimeSpan(start: NOMADSTest.at(14), end: NOMADSTest.at(2, days: 1))

    @Test func outsideTheHRRRDomainThrowsWithoutARequest() async throws {
        let stub = try StubNOMADS()
        stub.finish()
        let smoke = HRRRSmokeProvider(http: stub.http, clock: ManualSourceClock(now: now))
        do { _ = try await smoke.forecast(at: S, span: span); Issue.record("expected an error") } catch {
            #expect(SourceError.wrap(error) == .outsideCoverage)
        }
        #expect(stub.http.requests.isEmpty)
    }

    @Test func rowsCarryOnlySmokeAndAerosol() async throws {
        let stub = try StubNOMADS()
        stub.postHRRR(cycle: NOMADSTest.at(13), hours: 1...18)
        stub.finish()
        let smoke = HRRRSmokeProvider(http: stub.http, clock: ManualSourceClock(now: now))
        let r = try await smoke.forecast(at: W, span: span)
        #expect(r.value.hours.count == 13)
        #expect(r.value.hours.allSatisfy { Set($0.presentFields) == [.smokeUgm3, .aod550] })
        #expect(r.value.fieldSources == [.smokeUgm3: .noaaHRRRSmoke, .aod550: .noaaHRRRSmoke])
        #expect(r.provenance.source == .noaaHRRRSmoke)
        #expect(r.provenance.model == "HRRR 2026-11-22 13Z f01–f13")
        #expect(stub.http.requests.count == 13 && stub.http.requests.allSatisfy { $0.source == .noaaHRRRSmoke })
        #expect(stub.http.requests.allSatisfy { $0.url.absoluteString.contains("var_MASSDEN=on&var_COLMD=on&var_AOTK=on") })
        // f01 at W (ecCodes nearest MASSDEN 0.02 ug/m3 in the fixture data).
        let first = try #require(r.value.hours.first)
        #expect(abs((first.smokeUgm3 ?? -1) - 0.02) < 0.01)
    }

    @Test func smokeReusesTheForecastProvidersBoxes() async throws {
        let stub = try StubNOMADS()
        stub.postHRRR(cycle: NOMADSTest.at(13), hours: 1...18)
        stub.finish()
        let clock = ManualSourceClock(now: now)
        let cache = InMemoryBlobCache(clock: clock)
        let forecast = NOMADSForecastProvider(http: stub.http, clock: clock, cache: cache)
        _ = try await forecast.forecast(at: W, span: span)
        #expect(stub.http.requests.count == 13)
        let smoke = HRRRSmokeProvider(sharing: forecast)
        let r = try await smoke.forecast(at: W, span: span)
        #expect(stub.http.requests.count == 13, "smoke from the shared cache costs nothing")
        #expect(r.value.hours.count == 13)
        // Same cache, separate instance: also free.
        let other = HRRRSmokeProvider(http: stub.http, clock: clock, cache: cache)
        _ = try await other.forecast(at: W, span: span)
        #expect(stub.http.requests.count == 13)
    }

    @Test func descriptorsAreTheCatalogueOnes() {
        let stub = StubHTTPClient()
        let f = NOMADSForecastProvider(http: stub)
        #expect(f.descriptor.id == .noaaNOMADS && f.descriptor.kinds == [.forecast, .nowcast])
        let s = HRRRSmokeProvider(http: stub)
        #expect(s.descriptor.id == .noaaHRRRSmoke && s.descriptor.kinds == [.smoke, .aerosol])
    }
}
