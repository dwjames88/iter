import Foundation
import Testing
import IterModel
import IterSources
@testable import IterSourcesLive

private func utc(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }
private let whitney = Coordinate(latitude: 36.5785, longitude: -118.2923)
private let gotthard = Coordinate(latitude: 46.5586, longitude: 8.5610)
private let fairbanks = Coordinate(latitude: 64.8378, longitude: -147.7164)
/// 2026-11-22T13:45:00Z: 49 minutes after KBIH's recorded observation (12:56Z).
private let now = utc("2026-11-22T13:45:00Z")

@Suite("NWSMapping")
struct NWSMappingTests {
    @Test func emptyAlertsAtWhitney() throws {
        let r = try NWSMapping.alerts(from: Fixtures.data("NWS/alerts-active-W.json"))
        #expect(r.alerts.isEmpty)
        #expect(r.updated == utc("2026-11-22T13:45:02Z"))
    }

    @Test func alaskaAlerts() throws {
        let r = try NWSMapping.alerts(from: Fixtures.data("NWS/alerts-active-area-AK.json"))
        #expect(r.alerts.count == 10)
        #expect(r.updated == utc("2026-11-22T14:15:02Z"))
        #expect(r.alerts.map(\.event) == [
            "Special Weather Statement", "High Surf Advisory", "High Surf Advisory", "High Surf Advisory", "High Wind Warning",
            "High Surf Advisory", "Wind Advisory", "Wind Advisory", "Air Quality Alert", "Special Weather Statement",
        ])
        let sps = r.alerts[0]
        #expect(sps.id == "urn:oid:2.49.0.1.840.0.da505aa5f9bbc7c506a6242d56e06d55081389c8.001.1")
        #expect(sps.severity == .moderate)
        #expect(sps.urgency == "Expected")
        #expect(sps.certainty == "Observed")
        #expect(sps.onset == utc("2026-11-22T12:12:00Z"))  // 03:12 at UTC-9
        #expect(sps.ends == nil)
        #expect(sps.expires == utc("2026-11-23T00:00:00Z"))  // 15:00 at UTC-9
        #expect(sps.senderName == "NWS Fairbanks AK")
        #expect(sps.headline == "Special Weather Statement issued November 22 at 3:12AM AKST by NWS Fairbanks AK")
        #expect(sps.instruction == nil)
        #expect(sps.areaDescription?.hasPrefix("Lower Kobuk Valley; Baldwin Peninsula") == true)
        #expect(sps.description?.hasPrefix("Minor coastal erosion and high surf") == true)
        #expect(sps.url?.absoluteString == "https://api.weather.gov/alerts/" + sps.id)

        let wind = r.alerts[4]
        #expect(wind.severity == .severe)
        #expect(wind.areaDescription == "St Lawrence Island")
        #expect(wind.onset == utc("2026-11-23T03:00:00Z"))
        #expect(wind.ends == utc("2026-11-23T18:00:00Z"))
        #expect(wind.expires == utc("2026-11-23T00:00:00Z"))
        #expect(wind.instruction?.hasPrefix("People are urged to secure loose objects") == true)
        #expect(wind.description?.contains("gusts up to 60 mph") == true)

        let surf = r.alerts[1]
        #expect(surf.severity == .minor)
        #expect(surf.ends == utc("2026-11-24T09:00:00Z"))
        let air = r.alerts[8]
        #expect(air.severity == .unknown)
        #expect(air.urgency == "Unknown")
        #expect(air.ends == nil)
        #expect(Set(r.alerts.map(\.id)).count == 10)
    }

    @Test func severityMapping() {
        #expect(NWSMapping.severity("Extreme") == .extreme)
        #expect(NWSMapping.severity("Severe") == .severe)
        #expect(NWSMapping.severity("Moderate") == .moderate)
        #expect(NWSMapping.severity("Minor") == .minor)
        #expect(NWSMapping.severity("Unknown") == .unknown)
        #expect(NWSMapping.severity(nil) == .unknown)
    }

    @Test func pointsAndStations() throws {
        #expect(try NWSMapping.observationStationsURL(fromPoints: Fixtures.data("NWS/points-W.json")).absoluteString
            == "https://api.weather.gov/gridpoints/VEF/14,134/stations")
        #expect(throws: SourceError.self) { try NWSMapping.observationStationsURL(fromPoints: Fixtures.data("NWS/points-S.json")) }
        let s = try NWSMapping.stations(from: Fixtures.data("NWS/gridpoints-VEF-14-134-stations.json"))
        #expect(s.map(\.id) == ["KO26", "KBIH", "DYNN2", "DEVC1", "CMP03"])
        #expect(s[0].name == "Lone Pine/Death Valley Airport")
        #expect(abs(s[0].coordinate.latitude - 36.58869) < 1e-9)
        #expect(abs(s[0].coordinate.longitude + 118.04939) < 1e-9)
    }

    @Test func bishopObservationKeepsNullsNil() throws {
        let l = try #require(try NWSMapping.latestObservation(from: Fixtures.data("NWS/stations-KBIH-observations-latest.json")))
        #expect(l.stationID == "KBIH")
        #expect(l.rawMessage?.hasPrefix("KBIH 221256Z AUTO 30006KT") == true)
        let o = l.observation
        #expect(o.time == utc("2026-11-22T12:56:00Z"))
        #expect(o.stationName == "Bishop, Bishop Airport")
        let c = o.conditions
        #expect(c.tempC == nil && c.dewpointC == nil && c.windMs == nil && c.gustMs == nil && c.windDirDeg == nil)
        #expect(c.rhPercent == nil)  // not computed: the null stays null
        #expect(c.precipMm == nil)
        #expect(abs(c.visibilityKm! - 16.09) < 1e-9)
        #expect(c.cloudTotal == 0.75)
        #expect(c.cloudBaseM == 3660)
        #expect(c.cloudLow == 0)
        #expect(c.cloudMid == 0.75)
        #expect(c.cloudHigh == nil)
    }

    @Test func unitsAreConverted() throws {
        let json = """
        {"properties":{"stationId":"KTST","stationName":"Test","timestamp":"2026-11-22T13:00:00+00:00",
        "temperature":{"unitCode":"wmoUnit:degC","value":10.5},"dewpoint":{"unitCode":"wmoUnit:degC","value":4.0},
        "windDirection":{"unitCode":"wmoUnit:degree_(angle)","value":270},
        "windSpeed":{"unitCode":"wmoUnit:km_h-1","value":36},"windGust":{"unitCode":"wmoUnit:km_h-1","value":54},
        "visibility":{"unitCode":"wmoUnit:m","value":8000},"relativeHumidity":{"unitCode":"wmoUnit:percent","value":55.2},
        "barometricPressure":{"unitCode":"wmoUnit:Pa","value":101300},
        "precipitationLastHour":{"unitCode":"wmoUnit:mm","value":1.2},
        "cloudLayers":[{"base":{"unitCode":"wmoUnit:m","value":300},"amount":"FEW"},{"base":{"unitCode":"wmoUnit:m","value":7000},"amount":"OVC"}]}}
        """
        let c = try #require(try NWSMapping.latestObservation(from: Data(json.utf8))).observation.conditions
        #expect(c.tempC == 10.5 && c.dewpointC == 4)
        #expect(c.windDirDeg == 270)
        #expect(c.windMs == 10)
        #expect(c.gustMs == 15)
        #expect(c.visibilityKm == 8)
        #expect(c.rhPercent == 55.2)
        #expect(c.precipMm == 1.2)
        #expect(c.cloudTotal == 1)
        #expect(c.cloudLow == 0.19)
        #expect(c.cloudHigh == 1)
        #expect(c.cloudBaseM == 7000)
    }

    @Test func observationWithoutTimestampIsNil() throws {
        #expect(try NWSMapping.latestObservation(from: Data(#"{"properties":{"stationId":"X"}}"#.utf8)) == nil)
    }

    @Test func problemDocumentIsDecodingError() {
        #expect(throws: SourceError.self) { try NWSMapping.alerts(from: Data("<html>".utf8)) }
    }
}

@Suite("NWSProvider")
struct NWSProviderTests {
    private func provider(_ stub: StubHTTPClient) -> NWSProvider {
        NWSProvider(http: stub, clock: ManualSourceClock(now: now))
    }

    private func observationStub() throws -> StubHTTPClient {
        let stub = StubHTTPClient()
        stub.on(urlContaining: "/points/36.5785,-118.2923", reply: .ok(try Fixtures.data("NWS/points-W.json")))
        stub.on(urlContaining: "/gridpoints/VEF/14,134/stations", reply: .ok(try Fixtures.data("NWS/gridpoints-VEF-14-134-stations.json")))
        stub.on(urlContaining: "/stations/KO26/observations/latest", reply: .status(404, Data(#"{"title":"Not Found"}"#.utf8)))
        stub.on(urlContaining: "/stations/KBIH/observations/latest", reply: .ok(try Fixtures.data("NWS/stations-KBIH-observations-latest.json")))
        return stub
    }

    @Test func outsideCoverageMakesNoRequest() async {
        let stub = StubHTTPClient()
        await #expect(throws: SourceError.outsideCoverage) { try await provider(stub).alerts(at: gotthard) }
        await #expect(throws: SourceError.outsideCoverage) { try await provider(stub).latest(near: gotthard, within: 50, maxAge: .seconds(3600)) }
        #expect(stub.requests.isEmpty)
    }

    @Test func apiInvalidPointIsOutsideCoverage() async throws {
        let stub = StubHTTPClient()
        stub.on(urlContaining: "/points/", reply: .status(404, try Fixtures.data("NWS/points-S.json")))
        // A US coordinate (inside our coarse shape) that the API itself rejects.
        let c = Coordinate(latitude: 40.0, longitude: -100.0)
        await #expect(throws: SourceError.outsideCoverage) { try await provider(stub).latest(near: c, within: 50, maxAge: .seconds(3600)) }
        #expect(stub.requests.count == 1)
    }

    @Test func emptyAlertsEndToEnd() async throws {
        let stub = StubHTTPClient()
        stub.on(urlContaining: "/alerts/active", reply: .ok(try Fixtures.data("NWS/alerts-active-W.json")))
        let r = try await provider(stub).alerts(at: Coordinate(latitude: 36.578_5001, longitude: -118.292_3004))
        #expect(r.value.isEmpty)
        #expect(r.provenance.source == .nwsAPI)
        #expect(r.provenance.issuedAt == utc("2026-11-22T13:45:02Z"))
        #expect(r.provenance.fetchedAt == now)
        let req = try #require(stub.requests.first)
        #expect(req.url.absoluteString == "https://api.weather.gov/alerts/active?point=36.5785,-118.2923")
        #expect(req.headers["Accept"] == "application/geo+json")
        #expect(req.headers.count == 1)
    }

    @Test func alertsEndToEnd() async throws {
        let stub = StubHTTPClient()
        stub.on(urlContaining: "/alerts/active", reply: .ok(try Fixtures.data("NWS/alerts-active-area-AK.json")))
        let r = try await provider(stub).alerts(at: fairbanks)
        #expect(r.value.count == 10)
        #expect(r.value[4].event == "High Wind Warning")
        #expect(stub.requests[0].url.absoluteString == "https://api.weather.gov/alerts/active?point=64.8378,-147.7164")
    }

    @Test func alertErrors() async throws {
        let limited = StubHTTPClient()
        limited.on(urlContaining: "/alerts/active", reply: .status(429))
        await #expect(throws: SourceError.rateLimited(retryAfter: nil)) { try await provider(limited).alerts(at: whitney) }
        let down = StubHTTPClient()
        down.on(urlContaining: "/alerts/active", reply: .status(503, Data("maintenance".utf8)))
        await #expect(throws: SourceError.http(status: 503, excerpt: "maintenance")) { try await provider(down).alerts(at: whitney) }
    }

    @Test func latestFallsBackToNextStation() async throws {
        let stub = try observationStub()
        let r = try await provider(stub).latest(near: whitney, within: 100, maxAge: .seconds(2 * 3600))
        #expect(r.count == 1)
        let obs = try #require(r.first)
        #expect(obs.value.stationName == "Bishop, Bishop Airport")
        #expect(obs.value.time == utc("2026-11-22T12:56:00Z"))
        #expect(abs(obs.value.conditions.visibilityKm! - 16.09) < 1e-9)
        #expect(obs.provenance.source == .nwsAPI)
        #expect(obs.provenance.issuedAt == utc("2026-11-22T12:56:00Z"))
        #expect(obs.provenance.fetchedAt == now)
        #expect(abs(obs.provenance.distanceKm! - 88.3) < 0.2)
        #expect(obs.provenance.origin?.tier == .government)
        #expect(obs.provenance.origin?.producer == "NOAA National Weather Service")

        // KO26 (nearest) was tried and failed with 404, then KBIH; DYNN2 and the rest are beyond 100 km.
        #expect(stub.requests.map(\.url.absoluteString) == [
            "https://api.weather.gov/points/36.5785,-118.2923",
            "https://api.weather.gov/gridpoints/VEF/14,134/stations",
            "https://api.weather.gov/stations/KO26/observations/latest",
            "https://api.weather.gov/stations/KBIH/observations/latest",
        ])
        #expect(stub.requests.allSatisfy { $0.headers["Accept"] == "application/geo+json" })
    }

    @Test func staleObservationsAreRejected() async throws {
        let stub = try observationStub()
        let r = try await provider(stub).latest(near: whitney, within: 100, maxAge: .seconds(30 * 60))  // KBIH is 49 minutes old
        #expect(r.isEmpty)
    }

    @Test func noStationWithinRange() async throws {
        let stub = try observationStub()
        let r = try await provider(stub).latest(near: whitney, within: 5, maxAge: .seconds(2 * 3600))
        #expect(r.isEmpty)
        #expect(stub.requests.count == 2)  // points and stations only
    }

    @Test func pointsFailureOtherThan404Propagates() async throws {
        let stub = StubHTTPClient()
        stub.on(urlContaining: "/points/", reply: .status(500, Data("boom".utf8)))
        await #expect(throws: SourceError.http(status: 500, excerpt: "boom")) {
            try await provider(stub).latest(near: whitney, within: 50, maxAge: .seconds(3600))
        }
    }

    @Test func descriptorIsTheCatalogues() {
        let p = provider(StubHTTPClient())
        #expect(p.descriptor == SourceCatalogue.nwsAPI)
        #expect(p.descriptor.kinds == [.alerts, .observation])
    }
}
