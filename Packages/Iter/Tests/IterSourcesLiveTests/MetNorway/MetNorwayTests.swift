import Foundation
import Testing
import IterModel
import IterSources
@testable import IterSourcesLive

private func utc(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }

private let whitney = Coordinate(latitude: 36.5785, longitude: -118.2923)
private let gotthard = Coordinate(latitude: 46.5586, longitude: 8.5610)
private let fullSpan = TimeSpan(start: utc("2026-11-22T00:00:00Z"), end: utc("2026-12-31T00:00:00Z"))

@Suite("MetNorwayMapping")
struct MetNorwayMappingTests {
    @Test func whitneyFirstHour() throws {
        let f = try MetNorwayMapping.forecast(from: Fixtures.data("MetNo/locationforecast-W.json"), span: nil)
        #expect(f.hours.count == 93)
        #expect(f.updatedAt == utc("2026-11-22T13:16:19Z"))
        let h = try #require(f.hours.first)
        #expect(h.time == utc("2026-11-22T13:00:00Z"))
        // Recorded run (SOURCES.md quoted an earlier run: 2.3/20.3/35.2 at 13Z).
        #expect(h.cloudTotal == 0.414)
        #expect(h.cloudLow == 0.008)
        #expect(abs(h.cloudMid! - 0.211) < 1e-12)
        #expect(h.cloudHigh == 0.266)
        #expect(h.tempC == -15.1)
        #expect(h.dewpointC == -27.3)
        #expect(h.rhPercent == 36.5)
        #expect(h.windMs == 0.5)
        #expect(h.windDirDeg == 229.1)
        #expect(h.precipMm == 0.0)
        #expect(h.gustMs == nil)
        #expect(h.precipChance == nil)
        #expect(h.visibilityKm == nil)
        #expect(h.cloudBaseM == nil)
    }

    @Test func gotthardFirstHour() throws {
        let f = try MetNorwayMapping.forecast(from: Fixtures.data("MetNo/locationforecast-S.json"), span: nil)
        #expect(f.updatedAt == utc("2026-11-22T13:16:56Z"))
        let h = try #require(f.hours.first)
        #expect(h.cloudTotal == 1.0)
        #expect(h.cloudLow == 1.0)
        #expect(h.cloudMid == 0.937)
        #expect(abs(h.cloudHigh! - 0.844) < 1e-12)
        #expect(h.tempC == -2.9)
        #expect(h.dewpointC == -4.2)
        #expect(h.rhPercent == 90.7)
        #expect(h.windMs == 1.5)
        #expect(h.windDirDeg == 198.8)
        #expect(h.precipMm == 0.5)
        // fog_area_fraction is 1.6 here, and must not turn into a visibility.
        #expect(h.visibilityKm == nil)
    }

    @Test func nativeStepsAndNoSmearing() throws {
        let f = try MetNorwayMapping.forecast(from: Fixtures.data("MetNo/locationforecast-W.json"), span: nil)
        // Hourly rows first, then 6-hourly from 2026-11-25T06:00Z (index 65).
        #expect(f.hours[64].time == utc("2026-11-25T05:00:00Z"))
        #expect(f.hours[64].precipMm == 0.0)
        #expect(f.hours[65].time == utc("2026-11-25T06:00:00Z"))
        #expect(f.hours[65].precipMm == nil)  // only next_6_hours (0.1 mm) exists: not spread
        #expect(f.hours[65].cloudLow == 0.023)
        #expect(f.hours[65].cloudMid == 0.469)
        #expect(f.hours[65].cloudHigh == 0.68)
        #expect(f.hours[66].time.timeIntervalSince(f.hours[65].time) == 6 * 3600)
        #expect(zip(f.hours, f.hours.dropFirst()).allSatisfy { $0.time < $1.time })
    }

    @Test func spanFilter() throws {
        let span = TimeSpan(start: utc("2026-11-22T14:00:00Z"), end: utc("2026-11-22T16:00:00Z"))
        let f = try MetNorwayMapping.forecast(from: Fixtures.data("MetNo/locationforecast-W.json"), span: span)
        #expect(f.hours.map(\.time) == [utc("2026-11-22T14:00:00Z"), utc("2026-11-22T15:00:00Z"), utc("2026-11-22T16:00:00Z")])
    }

    @Test func gustAndProbabilityWhenPresent() throws {
        let json = """
        {"properties":{"meta":{"updated_at":"2026-11-22T10:00:00Z"},"timeseries":[
        {"time":"2026-11-22T10:00:00Z","data":{"instant":{"details":{"wind_speed":4.0,"wind_speed_of_gust":9.5,"cloud_area_fraction":250.0}},
          "next_1_hours":{"details":{"precipitation_amount":1.2,"probability_of_precipitation":30.0}}}},
        {"time":"2026-11-22T16:00:00Z","data":{"instant":{"details":{"wind_speed":3.0}},
          "next_6_hours":{"details":{"precipitation_amount":2.0,"probability_of_precipitation":80.0}}}}]}}
        """
        let f = try MetNorwayMapping.forecast(from: Data(json.utf8), span: nil)
        #expect(f.hours[0].gustMs == 9.5)
        #expect(f.hours[0].precipChance == 0.3)
        #expect(f.hours[0].precipMm == 1.2)
        #expect(f.hours[0].cloudTotal == 1.0)  // clamped
        #expect(f.hours[1].precipChance == 0.8)
        #expect(f.hours[1].precipMm == nil)
        #expect(f.hours[1].gustMs == nil)
    }

    @Test func garbageIsDecodingError() {
        #expect(throws: SourceError.self) { try MetNorwayMapping.forecast(from: Data("<html>".utf8), span: nil) }
    }
}

@Suite("MetNorwayProvider")
struct MetNorwayProviderTests {
    private func provider(_ stub: StubHTTPClient) -> MetNorwayProvider {
        MetNorwayProvider(http: stub, clock: ManualSourceClock(now: utc("2026-11-22T13:45:00Z")))
    }

    @Test func urlRoundsToFourDecimals() {
        #expect(MetNorwayProvider.requestURL(for: whitney).absoluteString
            == "https://api.met.no/weatherapi/locationforecast/2.0/complete?lat=36.5785&lon=-118.2923")
        let precise = Coordinate(latitude: 36.578_549_9, longitude: -118.292_349_9)
        #expect(MetNorwayProvider.requestURL(for: precise).absoluteString.hasSuffix("lat=36.5785&lon=-118.2923"))
        #expect(MetNorwayProvider.requestURL(for: gotthard).absoluteString.hasSuffix("lat=46.5586&lon=8.561"))
        let whole = Coordinate(latitude: 46, longitude: 8)
        #expect(MetNorwayProvider.requestURL(for: whole).absoluteString.hasSuffix("lat=46&lon=8"))
    }

    @Test func forecastEndToEnd() async throws {
        let stub = StubHTTPClient()
        stub.on(urlContaining: "locationforecast/2.0/complete", reply: .ok(try Fixtures.data("MetNo/locationforecast-W.json")))
        let result = try await provider(stub).forecast(
            at: Coordinate(latitude: 36.578_549, longitude: -118.292_31), span: fullSpan)
        #expect(result.value.hours.count == 93)
        #expect(result.value.source(of: .cloudLow) == SourceID.metNorway)
        #expect(result.value.source(of: .visibilityKm) == nil)
        #expect(result.provenance.source == .metNorway)
        #expect(result.provenance.model == "MET Norway locationforecast 2.0")
        #expect(result.provenance.issuedAt == utc("2026-11-22T13:16:19Z"))
        #expect(result.provenance.fetchedAt == utc("2026-11-22T13:45:00Z"))
        #expect(result.provenance.url?.host == "www.yr.no")

        let req = try #require(stub.requests.first)
        #expect(stub.requests.count == 1)
        #expect(req.url.absoluteString == "https://api.met.no/weatherapi/locationforecast/2.0/complete?lat=36.5785&lon=-118.2923")
        #expect(req.method == "GET")
        #expect(req.headers.isEmpty)  // no User-Agent, no cache-busting header
        #expect(req.policy.honourExpires)
        #expect(req.policy.conditional)
        let items = URLComponents(url: req.url, resolvingAgainstBaseURL: false)?.queryItems?.map(\.name)
        #expect(items == ["lat", "lon"])
    }

    @Test func spanIsApplied() async throws {
        let stub = StubHTTPClient()
        stub.on(urlContaining: "locationforecast", reply: .ok(try Fixtures.data("MetNo/locationforecast-S.json")))
        let span = TimeSpan(start: utc("2026-11-22T13:00:00Z"), end: utc("2026-11-22T14:00:00Z"))
        let result = try await provider(stub).forecast(at: gotthard, span: span)
        #expect(result.value.hours.count == 2)
        #expect(result.provenance.validFor == span)
    }

    @Test func httpErrorsAreMapped() async throws {
        let stub = StubHTTPClient()
        stub.on(urlContaining: "locationforecast", reply: .status(403, Data("Forbidden".utf8)))
        await #expect(throws: SourceError.http(status: 403, excerpt: "Forbidden")) {
            try await provider(stub).forecast(at: whitney, span: fullSpan)
        }
        let offline = StubHTTPClient()
        offline.on(urlContaining: "locationforecast", reply: .error(.offline))
        await #expect(throws: SourceError.offline) { try await provider(offline).forecast(at: whitney, span: fullSpan) }
    }

    @Test func badCoordinateMakesNoRequest() async {
        let stub = StubHTTPClient()
        await #expect(throws: SourceError.self) {
            try await provider(stub).forecast(at: Coordinate(latitude: 95, longitude: 0), span: fullSpan)
        }
        #expect(stub.requests.isEmpty)
    }
}
