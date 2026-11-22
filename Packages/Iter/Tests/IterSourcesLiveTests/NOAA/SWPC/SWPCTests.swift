import Foundation
import Testing
import IterModel
import IterSources
@testable import IterSourcesLive

/// Oracle for exact instants: Foundation's own ISO 8601 parser, independent of the mapping's arithmetic.
func w4ISODate(_ s: String) -> Date {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f.date(from: s)!
}

@Suite("SWPC aurora mapping")
struct SWPCMappingTests {
    static let grid: SWPCMapping.OvationGrid = {
        try! SWPCMapping.ovation(from: Fixtures.data("SWPC/ovation_aurora_latest.json"))
    }()

    @Test func timesAreExactUTC() {
        #expect(Self.grid.observedAt == w4ISODate("2026-11-22T13:38:00Z"))
        #expect(Self.grid.forecastFor == w4ISODate("2026-11-22T14:45:00Z"))
    }

    @Test func gridHoldsEveryCell() throws {
        // 360 x 181 cells, all listed in the recorded file.
        for lon in stride(from: 0, to: 360, by: 37) {
            for lat in stride(from: -90, through: 90, by: 30) {
                #expect(Self.grid.probability(at: Coordinate(latitude: Double(lat), longitude: Double(lon))) != nil)
            }
        }
    }

    @Test func nearestCellProbabilities() {
        // Whitney (W): 36.5785, -118.2923 -> cell lon 242 (241.71), lat 37: 0 %.
        #expect(SWPCMapping.OvationGrid.cell(for: Coordinate(latitude: 36.5785, longitude: -118.2923)) == (242, 37))
        #expect(Self.grid.probability(at: Coordinate(latitude: 36.5785, longitude: -118.2923)) == 0)
        // Fairbanks: 64.8, -147.7 -> cell lon 212 (212.3), lat 65: 4 % in the recorded file (the cell north of it, 66, differs).
        #expect(SWPCMapping.OvationGrid.cell(for: Coordinate(latitude: 64.8, longitude: -147.7)) == (212, 65))
        #expect(Self.grid.probability(at: Coordinate(latitude: 64.8, longitude: -147.7)) == 4)
        // Southern hemisphere: -75.2, 140.3 -> cell (140, -75): 1 %.
        #expect(SWPCMapping.OvationGrid.cell(for: Coordinate(latitude: -75.2, longitude: 140.3)) == (140, -75))
        #expect(Self.grid.probability(at: Coordinate(latitude: -75.2, longitude: 140.3)) == 1)
        // Swiss Alps (S): cell (9, 47).
        #expect(SWPCMapping.OvationGrid.cell(for: Coordinate(latitude: 46.5586, longitude: 8.561)) == (9, 47))
        #expect(Self.grid.probability(at: Coordinate(latitude: 46.5586, longitude: 8.561)) == 0)
    }

    @Test func longitudeWrapsAtTheSeam() {
        // Recorded row at latitude -46: cells 358, 359, 0, 1 = 1, 1, 1, 0.  At 74: 6, 6, 6, 5.
        #expect(Self.grid.probability(at: Coordinate(latitude: -46, longitude: -0.4)) == 1)   // 359.6 -> cell 0
        #expect(Self.grid.probability(at: Coordinate(latitude: -46, longitude: 0.6)) == 0)    // cell 1
        #expect(Self.grid.probability(at: Coordinate(latitude: 74, longitude: 0.6)) == 5)
        #expect(Self.grid.probability(at: Coordinate(latitude: 74, longitude: -0.6)) == 6)    // 359.4 -> cell 359
        #expect(SWPCMapping.OvationGrid.cell(for: Coordinate(latitude: 0, longitude: -0.4)).longitude == 0)
        #expect(SWPCMapping.OvationGrid.cell(for: Coordinate(latitude: 0, longitude: 359.6)).longitude == 0)
        #expect(SWPCMapping.OvationGrid.cell(for: Coordinate(latitude: 0, longitude: 180)).longitude == 180)
        #expect(SWPCMapping.OvationGrid.cell(for: Coordinate(latitude: 0, longitude: -180)).longitude == 180)
    }

    @Test func seamOnASyntheticGridWhereNeighboursDiffer() throws {
        var triples: [[Double]] = []
        for lon in 0..<360 { for lat in -90...90 { triples.append([Double(lon), Double(lat), lon == 0 ? 50 : (lon == 359 ? 10 : 0)]) } }
        let g = try SWPCMapping.OvationGrid(observedAt: w4ISODate("2026-01-01T00:00:00Z"), forecastFor: w4ISODate("2026-01-01T01:00:00Z"),
                                            triples: triples)
        #expect(g.probability(at: Coordinate(latitude: 60, longitude: -0.4)) == 50)
        #expect(g.probability(at: Coordinate(latitude: 60, longitude: 359.6)) == 50)
        #expect(g.probability(at: Coordinate(latitude: 60, longitude: 0.4)) == 50)
        #expect(g.probability(at: Coordinate(latitude: 60, longitude: -0.6)) == 10)
        #expect(g.probability(at: Coordinate(latitude: 60, longitude: 359.4)) == 10)
        #expect(g.probability(at: Coordinate(latitude: -90, longitude: 0)) == 50)
        #expect(g.probability(at: Coordinate(latitude: 90, longitude: 0)) == 50)
    }

    @Test func malformedGridsAreDecodingErrors() {
        #expect(throws: SourceError.self) { try SWPCMapping.ovation(from: Data("[]".utf8)) }
        let bad = #"{"Observation Time":"x","Forecast Time":"y","coordinates":[[0,0,1]]}"#
        #expect(throws: SourceError.self) { try SWPCMapping.ovation(from: Data(bad.utf8)) }
        let outside = #"{"Observation Time":"2026-11-22T13:38:00Z","Forecast Time":"2026-11-22T14:45:00Z","coordinates":[[400,0,1]]}"#
        #expect(throws: SourceError.self) { try SWPCMapping.ovation(from: Data(outside.utf8)) }
    }

    @Test func kpNowTakesTheLatestRow() throws {
        let kp = try SWPCMapping.kpNow(from: Fixtures.data("SWPC/planetary_k_index_1m.json"))
        #expect(kp.kp == 0.33)
        #expect(kp.observedAt == w4ISODate("2026-11-22T13:42:00Z"))
    }

    @Test func kpFallsBackToIndexThenLabel() throws {
        let intOnly = #"[{"time_tag":"2026-11-22T13:42:00","kp_index":3,"kp":"3Z"}]"#
        #expect(try SWPCMapping.kpNow(from: Data(intOnly.utf8)).kp == 3)
        let labelOnly = #"[{"time_tag":"2026-11-22T13:42:00","kp":"1Z"},{"time_tag":"2026-11-22T13:41:00","kp":"5Z"}]"#
        let k = try SWPCMapping.kpNow(from: Data(labelOnly.utf8))
        #expect(k.kp == 1)
        #expect(k.observedAt == w4ISODate("2026-11-22T13:42:00Z"))
        #expect(abs(SWPCMapping.kp(fromLabel: "2P")! - 7.0 / 3.0) < 1e-9)
        #expect(abs(SWPCMapping.kp(fromLabel: "2M")! - 5.0 / 3.0) < 1e-9)
        #expect(SWPCMapping.kp(fromLabel: "banana") == nil)
        #expect(throws: SourceError.self) { try SWPCMapping.kpNow(from: Data("[]".utf8)) }
    }

    @Test func kpForecastFixture() throws {
        let periods = try SWPCMapping.kpForecast(from: Fixtures.data("SWPC/noaa-planetary-k-index-forecast.json"))
        #expect(periods.count == 81)
        #expect(periods.first == KpPeriod(start: w4ISODate("2026-11-15T00:00:00Z"), kp: 2.0, kind: .observed))
        #expect(periods.last == KpPeriod(start: w4ISODate("2026-11-25T00:00:00Z"), kp: 1.67, kind: .predicted))
        #expect(periods.filter { $0.kind == .observed }.count == 60)
        #expect(periods.filter { $0.kind == .estimated }.count == 4)
        #expect(periods.filter { $0.kind == .predicted }.count == 17)
        #expect(periods.contains(KpPeriod(start: w4ISODate("2026-11-19T00:00:00Z"), kp: 5.0, kind: .observed, noaaScale: "G1")))
        #expect(periods.filter { $0.noaaScale != nil }.count == 1)
        #expect(zip(periods, periods.dropFirst()).allSatisfy { $0.start < $1.start })
        #expect(periods.filter { $0.kind == .estimated }.map(\.start).first == w4ISODate("2026-11-22T12:00:00Z"))
    }

    @Test func kpForecastReadsTheHeaderRowShape() throws {
        let table = #"[["time_tag","kp","observed","noaa_scale"],["2026-11-22 03:00:00","2.33","observed",null],["2026-11-22 00:00:00","6.00","predicted","G2"]]"#
        let p = try SWPCMapping.kpForecast(from: Data(table.utf8))
        #expect(p.map(\.kp) == [6.0, 2.33])
        #expect(p[0].noaaScale == "G2" && p[0].start == w4ISODate("2026-11-22T00:00:00Z"))
        let unknown = #"[{"time_tag":"2026-11-22T00:00:00","kp":1.0,"observed":"guess","noaa_scale":null}]"#
        #expect(throws: SourceError.self) { try SWPCMapping.kpForecast(from: Data(unknown.utf8)) }
    }

    @Test func timeParsingNeverGuessesAZone() {
        #expect(SWPCUTC.parse("2026-11-22T13:38:00Z") == w4ISODate("2026-11-22T13:38:00Z"))
        #expect(SWPCUTC.parse("2026-11-22T13:38:00") == w4ISODate("2026-11-22T13:38:00Z"))
        #expect(SWPCUTC.parse("2024-02-29 23:59:59") == w4ISODate("2024-02-29T23:59:59Z"))
        #expect(SWPCUTC.parse("2026-11-22T13:38:00+02:00") == nil)
        #expect(SWPCUTC.parse("2026-13-22T13:38:00") == nil)
        #expect(SWPCUTC.parse("tomorrow") == nil)
        let d = w4ISODate("2031-03-09T04:05:06Z")
        #expect(SWPCUTC.iso(d) == "2031-03-09T04:05:06Z")
    }
}

@Suite("SWPC aurora provider")
struct SWPCProviderTests {
    static func stub(kp: StubHTTPClient.Reply? = nil) throws -> StubHTTPClient {
        let http = StubHTTPClient()
        http.on(urlContaining: "ovation_aurora_latest.json", reply: .ok(try Fixtures.data("SWPC/ovation_aurora_latest.json")))
        http.on(urlContaining: "planetary_k_index_1m.json", reply: kp ?? .ok(try Fixtures.data("SWPC/planetary_k_index_1m.json")))
        http.on(urlContaining: "noaa-planetary-k-index-forecast.json",
                reply: .ok(try Fixtures.data("SWPC/noaa-planetary-k-index-forecast.json")))
        return http
    }

    @Test func auroraAtFairbanks() async throws {
        let http = try Self.stub()
        let clock = ManualSourceClock(now: w4ISODate("2026-11-22T13:50:00Z"))
        let provider = SWPCAuroraProvider(http: http, clock: clock)
        let r = try await provider.aurora(at: Coordinate(latitude: 64.8, longitude: -147.7))
        #expect(r.value.probabilityPercent == 4)
        #expect(r.value.observedAt == w4ISODate("2026-11-22T13:38:00Z"))
        #expect(r.value.forecastFor == w4ISODate("2026-11-22T14:45:00Z"))
        #expect(r.value.kpNow == 0.33)
        #expect(r.value.kpObservedAt == w4ISODate("2026-11-22T13:42:00Z"))
        #expect(r.provenance.source == .swpc)
        #expect(r.provenance.issuedAt == w4ISODate("2026-11-22T13:38:00Z"))
        #expect(r.provenance.fetchedAt == w4ISODate("2026-11-22T13:50:00Z"))
        #expect(r.provenance.licence.key == LicenceKey.noaaSWPC)
        #expect(http.requests.map(\.url.absoluteString) == [
            "https://services.swpc.noaa.gov/json/ovation_aurora_latest.json",
            "https://services.swpc.noaa.gov/json/planetary_k_index_1m.json",
        ])
    }

    @Test func aKpFailureDoesNotLoseTheAuroraValue() async throws {
        let http = try Self.stub(kp: .status(503))
        let r = try await SWPCAuroraProvider(http: http).aurora(at: Coordinate(latitude: 64.8, longitude: -147.7))
        #expect(r.value.probabilityPercent == 4)
        #expect(r.value.kpNow == nil && r.value.kpObservedAt == nil)
    }

    @Test func ovationFailureIsReported() async throws {
        let http = StubHTTPClient()
        http.on(urlContaining: "ovation", reply: .status(500))
        await #expect(throws: SourceError.http(status: 500, excerpt: "")) {
            try await SWPCAuroraProvider(http: http).aurora(at: Coordinate(latitude: 64.8, longitude: -147.7))
        }
    }

    @Test func invalidLatitudeMakesNoRequest() async throws {
        let http = try Self.stub()
        await #expect(throws: SourceError.invalidRequest("latitude must be within -90...90")) {
            try await SWPCAuroraProvider(http: http).aurora(at: Coordinate(latitude: 95, longitude: 0))
        }
        #expect(http.requests.isEmpty)
    }

    @Test func kpForecastProvider() async throws {
        let http = try Self.stub()
        let r = try await SWPCAuroraProvider(http: http, clock: ManualSourceClock(now: w4ISODate("2026-11-22T14:00:00Z"))).kpForecast()
        #expect(r.value.count == 81)
        #expect(r.provenance.issuedAt == w4ISODate("2026-11-22T21:00:00Z"))   // newest non-predicted period
        #expect(r.provenance.validFor?.end == w4ISODate("2026-11-25T03:00:00Z"))
        #expect(http.requests.map(\.url.absoluteString) == ["https://services.swpc.noaa.gov/products/noaa-planetary-k-index-forecast.json"])
    }
}
