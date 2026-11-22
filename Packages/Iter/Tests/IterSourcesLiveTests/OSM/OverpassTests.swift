import Testing
import Foundation
import IterModel
import IterSources
@testable import IterSourcesLive

private let whitney = Coordinate(latitude: 36.5785, longitude: -118.2923)
private let gotthard = Coordinate(latitude: 46.5586, longitude: 8.5610)

/// The recorded searches used a 6 km radius; this box is the same extent.
private func area(_ c: Coordinate, boundary: GeoPolygon? = nil) -> DiscoveryArea {
    DiscoveryArea(name: nil, region: GeoRegion(center: c, latitudeDelta: 0.108, longitudeDelta: 0.1344), boundary: boundary)
}

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

@Suite("Overpass query builder")
struct OverpassQueryBuilderTests {
    @Test func peakQueryIsExact() {
        let q = OverpassQueryBuilder.query(area: area(whitney), features: [.peak], limit: 50)
        #expect(q == "[out:json][timeout:25];(node[\"natural\"~\"^(peak|volcano)$\"][\"name\"](36.524500,-118.359500,36.632500,-118.225100););out center 50;")
    }

    @Test func waterfallsUseNwrAndRequireName() {
        let q = OverpassQueryBuilder.query(area: area(whitney), features: [.waterfall], limit: 10)
        #expect(q.contains("nwr[\"waterway\"=\"waterfall\"][\"name\"](36.524500,"))
    }

    @Test func lakeHasTwoAlternativesWithExtraTagAndNameRegex() {
        let q = OverpassQueryBuilder.query(area: area(whitney), features: [.lake], limit: 10)
        #expect(q.contains("nwr[\"natural\"=\"water\"][\"water\"~\"^(lake|reservoir)$\"][\"name\"]("))
        #expect(q.contains("nwr[\"natural\"=\"water\"][\"name\"~\"Lake\"]("))
    }

    @Test func statementsFollowFeatureOrderAndAllKindsBuild() {
        let q = OverpassQueryBuilder.query(area: area(whitney), features: Set(FeatureKind.allCases), limit: 100)
        #expect(q.hasPrefix("[out:json][timeout:25];(node[\"natural\"~\"^(peak|volcano)$\"]"))
        #expect(q.hasSuffix(");out center 100;"))
        #expect(q.contains("[\"natural\"=\"cave_entrance\"]"))
        #expect(q.contains("[\"historic\"=\"castle\"]"))
    }

    @Test func boundaryBoundingBoxReplacesRegion() {
        let ring = [(36.50, -118.40), (36.50, -118.20), (36.65, -118.20), (36.65, -118.40)].map { Coordinate(latitude: $0.0, longitude: $0.1) }
        let b = OverpassQueryBuilder.bbox(for: area(whitney, boundary: GeoPolygon(rings: [ring])))
        #expect(abs(b.south - 36.50) < 1e-9 && abs(b.north - 36.65) < 1e-9)
        #expect(abs(b.west + 118.40) < 1e-9 && abs(b.east + 118.20) < 1e-9)
    }

    /// The old app had this backwards (server query timeout longer than the client's).
    @Test func serverTimeoutIsBelowClientTimeout() throws {
        let q = OverpassQueryBuilder.query(area: area(whitney), features: [.peak], limit: 10)
        let server = try #require(OverpassQueryBuilder.serverTimeout(in: q))
        #expect(server == 25)
        #expect(Double(server) < SourceCatalogue.osmOverpass.policy.timeout.timeInterval)
    }
}

@Suite("Overpass mapping")
struct OverpassMappingTests {
    let d = SourceCatalogue.osmOverpass

    @Test func westFixtureYieldsTheThirtyTwoNamedPeaks() throws {
        // 36 elements: 32 peaks, 3 waterfalls and 1 viewpoint; the waterfalls and the viewpoint have no name.
        let data = try Fixtures.data("Overpass/overpass-W.json")
        let all = try OverpassMapping.candidates(from: data, area: area(whitney), features: [.peak, .viewpoint, .waterfall], limit: 500, descriptor: d, fetchedAt: t0)
        #expect(all.count == 32)
        #expect(all.allSatisfy { $0.featureKinds == [.peak] && $0.source == .osmOverpass })
        let whitneyPeak = try #require(all.first { $0.name == "Mount Whitney" })
        #expect(whitneyPeak.elevationMeters == 4419.6)
        #expect(whitneyPeak.externalID == "node/944865772")
        #expect(abs(try #require(whitneyPeak.coordinate).latitude - 36.5785905) < 1e-9)
        let muir = try #require(all.first { $0.name == "Mount Muir" })
        #expect(muir.elevationMeters == 4274.5)
        let carillon = try #require(all.first { $0.name == "Mount Carillon" })
        #expect(carillon.elevationMeters == 4135.4)
        let citation = try #require(whitneyPeak.citations.first)
        #expect(citation.url?.absoluteString == "https://www.openstreetmap.org/node/944865772")
        #expect(citation.licence == d.licence)
        #expect(citation.retrievedAt == t0)
    }

    @Test func southFixtureYieldsTheNamedPeaksAndOneNamedViewpoint() throws {
        // 47 elements: 38 peaks and 9 viewpoints, 8 of the viewpoints unnamed.
        let data = try Fixtures.data("Overpass/overpass-S.json")
        let all = try OverpassMapping.candidates(from: data, area: area(gotthard), features: [.peak, .viewpoint], limit: 500, descriptor: d, fetchedAt: t0)
        #expect(all.filter { $0.featureKinds == [.peak] }.count == 38)
        #expect(all.filter { $0.featureKinds == [.viewpoint] }.count == 1)
        let lucendro = try #require(all.first { $0.name == "Pizzo Lucendro" })
        #expect(lucendro.elevationMeters == 2963)
        #expect(try #require(all.first { $0.name == "Winterhorn" }).elevationMeters == 2660.8)
    }

    @Test func onlyRequestedKindsAreKept() throws {
        let data = try Fixtures.data("Overpass/overpass-S.json")
        let viewpoints = try OverpassMapping.candidates(from: data, area: area(gotthard), features: [.viewpoint], limit: 500, descriptor: d, fetchedAt: t0)
        #expect(viewpoints.count == 1)
        let lakes = try OverpassMapping.candidates(from: data, area: area(gotthard), features: [.lake], limit: 500, descriptor: d, fetchedAt: t0)
        #expect(lakes.isEmpty)
    }

    @Test func limitCapsTheResult() throws {
        let data = try Fixtures.data("Overpass/overpass-W.json")
        let some = try OverpassMapping.candidates(from: data, area: area(whitney), features: [.peak], limit: 5, descriptor: d, fetchedAt: t0)
        #expect(some.count == 5)
    }

    @Test func boundaryDropsElementsOutside() throws {
        // A small square around the summit: Mount Whitney is in; Mount Muir (36.5647) and Mount Carillon are out.
        let ring = [(36.570, -118.300), (36.570, -118.285), (36.590, -118.285), (36.590, -118.300)].map { Coordinate(latitude: $0.0, longitude: $0.1) }
        let a = area(whitney, boundary: GeoPolygon(rings: [ring]))
        let data = try Fixtures.data("Overpass/overpass-W.json")
        let kept = try OverpassMapping.candidates(from: data, area: a, features: [.peak], limit: 500, descriptor: d, fetchedAt: t0)
        #expect(kept.contains { $0.name == "Mount Whitney" })
        #expect(!kept.contains { $0.name == "Mount Muir" })
        #expect(kept.count < 32)
        #expect(kept.allSatisfy { a.contains($0.coordinate!) })
    }

    @Test func wayCentreNameFallbackAndDuplicates() throws {
        let json = """
        {"elements":[
         {"type":"way","id":7,"center":{"lat":1.5,"lon":2.5},"tags":{"natural":"water","water":"lake","name:en":"Lake Test"}},
         {"type":"node","id":8,"lat":1.5,"lon":2.5,"tags":{"natural":"water","water":"lake","name:en":"Lake Test"}},
         {"type":"node","id":9,"lat":1.6,"lon":2.5,"tags":{"natural":"water","water":"pond","name":"Pond"}},
         {"type":"node","id":9,"lat":1.6,"lon":2.5,"tags":{"natural":"water","water":"lake","name":"Same Id"}}
        ]}
        """
        let a = DiscoveryArea(name: nil, region: GeoRegion(center: Coordinate(latitude: 1.5, longitude: 2.5), latitudeDelta: 1, longitudeDelta: 1))
        let r = try OverpassMapping.candidates(from: Data(json.utf8), area: a, features: [.lake], limit: 10, descriptor: d, fetchedAt: t0)
        #expect(r.map(\.name) == ["Lake Test", "Same Id"])
        #expect(r[0].externalID == "way/7")
        #expect(r[0].coordinate == Coordinate(latitude: 1.5, longitude: 2.5))
        #expect(r[0].citations.first?.url?.absoluteString == "https://www.openstreetmap.org/way/7")
    }

    @Test func runtimeRemarkIsDetected() {
        let timeout = #"{"remark":"runtime error: Query timed out in \"query\" at line 1 after 26 seconds.","elements":[]}"#
        #expect(OverpassMapping.runtimeRemark(in: Data(timeout.utf8)) != nil)
        #expect(OverpassMapping.runtimeRemark(in: Data(#"{"elements":[]}"#.utf8)) == nil)
        #expect(OverpassMapping.runtimeRemark(in: Data("not json".utf8)) == nil)
    }

    @Test func garbageThrowsDecoding() {
        #expect(throws: SourceError.self) {
            try OverpassMapping.candidates(from: Data("<html>".utf8), area: area(whitney), features: [.peak], limit: 5, descriptor: d, fetchedAt: t0)
        }
    }

    @Test func elevationParsing() {
        let cases: [(String?, Double?)] = [
            ("4266", 4266), ("4266.5", 4266.5), (" 4266 m ", 4266), ("4266m", 4266), ("4266,5", 4266.5),
            ("14,000 ft", 14000 * 0.3048), ("14000'", 14000 * 0.3048), ("8,848", 8848), ("14,000", nil), ("1,234,567", nil),
            ("-12", -12), ("", nil), (nil, nil), ("high", nil), ("4266;4270", nil), ("~4266", nil), ("4266 km", nil), ("99999", nil),
        ]
        for (raw, expected) in cases {
            let got = OverpassMapping.elevation(raw)
            if let expected, let got { #expect(abs(got - expected) < 1e-9, "\(raw ?? "nil")") } else { #expect(got == expected, "\(raw ?? "nil")") }
        }
    }
}

@Suite("Overpass provider")
struct OverpassProviderTests {
    func fixture() throws -> Data { try Fixtures.data("Overpass/overpass-W.json") }

    func provider(_ http: StubHTTPClient, clock: ManualSourceClock) -> OverpassProvider {
        OverpassProvider(http: http, clock: clock)
    }

    @Test func okFromFirstServerSendsOnePostWithServerTimeoutBelowClient() async throws {
        let http = StubHTTPClient()
        http.on(urlContaining: "overpass-api.de", reply: .ok(try fixture()))
        let clock = ManualSourceClock(now: t0)
        let result = try await provider(http, clock: clock).candidates(in: area(whitney), features: [.peak], limit: 100)
        #expect(result.count == 32)
        #expect(clock.sleeps.isEmpty)
        let req = try #require(http.requests.first)
        #expect(http.requests.count == 1)
        #expect(req.method == "POST")
        #expect(req.url.absoluteString == "https://overpass-api.de/api/interpreter")
        #expect(req.headers["Content-Type"] == "application/x-www-form-urlencoded")
        #expect(req.policy.maxRetries == 0)
        let bodyData = try #require(req.body)
        let body = try #require(String(data: bodyData, encoding: .utf8))
        #expect(body.hasPrefix("data=%5Bout%3Ajson%5D%5Btimeout%3A25%5D"))
        // The server-side timeout in the body is shorter than the client timeout in the policy.
        let decoded = try #require(body.dropFirst(5).removingPercentEncoding)
        let server = try #require(OverpassQueryBuilder.serverTimeout(in: decoded))
        #expect(Double(server) < req.policy.timeout.timeInterval)
    }

    @Test func firstServer502RotatesToSecondAfterBackoff() async throws {
        let http = StubHTTPClient()
        http.on(urlContaining: "overpass-api.de", reply: .status(502, Data("Bad Gateway".utf8)))
        http.on(urlContaining: "overpass.private.coffee", reply: .ok(try fixture()))
        let clock = ManualSourceClock(now: t0)
        let result = try await provider(http, clock: clock).candidates(in: area(whitney), features: [.peak], limit: 100)
        #expect(result.count == 32)
        #expect(http.requests.map(\.url.host) == ["overpass-api.de", "overpass.private.coffee"])
        #expect(clock.sleeps == [.seconds(10)])
    }

    @Test func runtimeErrorRemarkCountsAsTimeoutAndRotates() async throws {
        let http = StubHTTPClient()
        let remark = #"{"remark":"runtime error: Query timed out in \"query\" at line 1 after 26 seconds.","elements":[]}"#
        http.on(urlContaining: "overpass-api.de", reply: .ok(Data(remark.utf8)))
        http.on(urlContaining: "overpass.private.coffee", reply: .status(504))
        http.on(urlContaining: "overpass.kumi.systems", reply: .ok(try fixture()))
        let clock = ManualSourceClock(now: t0)
        let result = try await provider(http, clock: clock).candidates(in: area(whitney), features: [.peak], limit: 100)
        #expect(result.count == 32)
        #expect(http.requests.count == 3)
        #expect(clock.sleeps == [.seconds(10), .seconds(20)])
    }

    @Test func badQueryFailsImmediatelyWithoutRotation() async throws {
        let http = StubHTTPClient()
        http.on(urlContaining: "overpass", reply: .status(400, Data("line 1: parse error".utf8)))
        let clock = ManualSourceClock(now: t0)
        await #expect {
            try await provider(http, clock: clock).candidates(in: area(whitney), features: [.peak], limit: 10)
        } throws: { error in
            guard case SourceError.invalidRequest(let m) = error else { return false }
            return m.contains("parse error")
        }
        #expect(http.requests.count == 1)
        #expect(clock.sleeps.isEmpty)
    }

    @Test func allServersFailGivesUpAfterThreeAttemptsWithLastError() async throws {
        let http = StubHTTPClient()
        http.on(urlContaining: "overpass-api.de", reply: .status(502))
        http.on(urlContaining: "overpass.private.coffee", reply: .error(.timedOut))
        http.on(urlContaining: "overpass.kumi.systems", reply: .status(503, Data("busy".utf8)))
        let clock = ManualSourceClock(now: t0)
        await #expect {
            try await provider(http, clock: clock).candidates(in: area(whitney), features: [.peak], limit: 10)
        } throws: { error in
            guard case SourceError.http(let status, _) = error else { return false }
            return status == 503
        }
        #expect(http.requests.count == 3)
        #expect(clock.sleeps == [.seconds(10), .seconds(20)])
    }

    @Test func rateLimitedHonoursRetryAfter() async throws {
        let http = StubHTTPClient()
        http.on(urlContaining: "overpass-api.de", reply: .error(.rateLimited(retryAfter: t0.addingTimeInterval(45))))
        http.on(urlContaining: "overpass.private.coffee", reply: .ok(try fixture()))
        let clock = ManualSourceClock(now: t0)
        _ = try await provider(http, clock: clock).candidates(in: area(whitney), features: [.peak], limit: 10)
        #expect(clock.sleeps == [.seconds(45)])
    }

    @Test func offlineDoesNotRetry() async throws {
        let http = StubHTTPClient()
        http.on(urlContaining: "overpass", reply: .error(.offline))
        let clock = ManualSourceClock(now: t0)
        await #expect(throws: SourceError.offline) {
            try await provider(http, clock: clock).candidates(in: area(whitney), features: [.peak], limit: 10)
        }
        #expect(http.requests.count == 1)
    }

    @Test func emptyFeaturesMakeNoRequest() async throws {
        let http = StubHTTPClient()
        let r = try await provider(http, clock: ManualSourceClock(now: t0)).candidates(in: area(whitney), features: [], limit: 10)
        #expect(r.isEmpty && http.requests.isEmpty)
    }
}
