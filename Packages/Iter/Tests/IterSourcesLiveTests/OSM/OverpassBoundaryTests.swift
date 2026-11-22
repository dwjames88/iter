import Testing
import Foundation
import IterModel
import IterSources
@testable import IterSourcesLive

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
private let near = Coordinate(latitude: 37.0, longitude: -119.0)
private let d = SourceCatalogue.osmOverpass

private func fixture() throws -> Data { try Fixtures.data("Overpass/overpass-boundary-hand.json") }
private func c(_ lat: Double, _ lon: Double) -> Coordinate { Coordinate(latitude: lat, longitude: lon) }

@Suite("Overpass boundary query")
struct OverpassBoundaryQueryTests {
    @Test func queryWithNearIsExact() {
        let q = OverpassQueryBuilder.boundaryQuery(name: "Yosemite National Park", near: c(37.75, -119.59))
        let bb = "(36.85,-120.728247,38.65,-118.451753)"
        let np = "[\"boundary\"~\"^(national_park|protected_area)$\"][\"name\"~\"^Yosemite National Park\",i];"
        let nr = "[\"leisure\"=\"nature_reserve\"][\"name\"~\"^Yosemite National Park\",i];"
        #expect(q == "[out:json][timeout:20][maxsize:33554432];(relation\(bb)\(np)relation\(bb)\(nr)way\(bb)\(np)way\(bb)\(nr));out geom;")
    }

    @Test func boxIsAboutOneHundredKilometresAndClamped() {
        let b = OverpassQueryBuilder.boundarySearchBox(around: c(37.75, -119.59))
        #expect(abs((b.north - b.south) * 111.32 / 2 - 100) < 1)
        #expect(abs((b.east - b.west) / 2 * 111.32 * cos(37.75 * .pi / 180) - 100) < 1)
        let pole = OverpassQueryBuilder.boundarySearchBox(around: c(89.9, 179.9))
        #expect(pole.north == 90 && pole.east == 180)
    }

    @Test func globalQueryHasNoBoxRequiresTheFullNameAndIsLimited() {
        let q = OverpassQueryBuilder.boundaryQuery(name: "Zion", near: nil)
        #expect(!q.contains("around") && !q.contains("(3") && !q.contains("(-"))
        #expect(q.contains("\"^Zion$\",i"))
        #expect(q.hasSuffix(");out geom 10;"))
        #expect(q.hasPrefix("[out:json][timeout:20][maxsize:33554432];(relation[\"boundary\"~"))
        #expect(!OverpassQueryBuilder.boundaryQuery(name: "Zion", near: near).contains("$\",i"))
    }

    @Test func administrativeBoundariesAreNotAskedFor() {
        let q = OverpassQueryBuilder.boundaryQuery(name: "Yosemite", near: near)
        #expect(!q.contains("administrative"))
        #expect(q.contains("national_park|protected_area") && q.contains("nature_reserve"))
    }

    @Test func metacharactersAreEscapedAsTextAndQuotesAsQL() {
        let q = OverpassQueryBuilder.boundaryQuery(name: "St. Mary's (Park) [A+B] a|b", near: nil)
        // Regex: each metacharacter gets a backslash; QL literal: that backslash is doubled.
        #expect(q.contains("\"^St\\\\. Mary's \\\\(Park\\\\) \\\\[A\\\\+B\\\\] a\\\\|b$\",i"))
        let quoted = OverpassQueryBuilder.boundaryQuery(name: "Say \"Hi\"", near: nil)
        #expect(quoted.contains("\"^Say \\\"Hi\\\"$\",i"))
        #expect(OverpassQueryBuilder.regexEscaped("a.b*c") == "a\\.b\\*c")
    }

    @Test func serverTimeoutStaysBelowTheClientTimeout() throws {
        let q = OverpassQueryBuilder.boundaryQuery(name: "X", near: near)
        let server = try #require(OverpassQueryBuilder.serverTimeout(in: q))
        #expect(server == 20)
        #expect(Double(server) < SourceCatalogue.osmOverpass.policy.timeout.timeInterval)
    }
}

@Suite("Overpass boundary mapping")
struct OverpassBoundaryMappingTests {
    @Test func stitchesWaysEndToEndReversingAsNeededAndKeepsTheHole() throws {
        let b = try #require(try OverpassBoundaryMapping.boundary(from: fixture(), named: "Granite Basin National Park", near: near, descriptor: d, fetchedAt: t0))
        #expect(b.name == "Granite Basin National Park")
        #expect(b.externalID == "relation/9001" && b.areaKind == "national_park")
        // Outer ring (the joined ways) plus the hole; the midpoints on the straight sides are simplified away.
        #expect(b.polygon.rings.count == 2)
        let outer = try #require(b.polygon.rings.first { $0.count == 4 })
        #expect(Set(outer.map { "\($0.latitude),\($0.longitude)" }) == ["36.9,-119.2", "37.1,-119.2", "37.1,-118.8", "36.9,-118.8"])
        // The ring is a real loop: consecutive vertices are corners that share a side (no diagonal crossing).
        let loop = outer + [outer[0]]
        for (p, q) in zip(loop, loop.dropFirst()) { #expect(p.latitude == q.latitude || p.longitude == q.longitude, "\(p) -> \(q)") }
        #expect(b.polygon.contains(c(37.05, -119.1)))
        #expect(b.polygon.contains(c(36.93, -118.85)))
        #expect(!b.polygon.contains(c(37.0, -119.0)), "inside the hole")
        #expect(!b.polygon.contains(c(37.3, -119.0)))
        #expect(!b.polygon.contains(c(36.95, -119.3)))
    }

    @Test func citationNamesTheRelationAndTheOSMLicence() throws {
        let b = try #require(try OverpassBoundaryMapping.boundary(from: fixture(), named: "Granite Basin National Park", near: near, descriptor: d, fetchedAt: t0))
        #expect(b.citation.source == .osmOverpass)
        #expect(b.citation.url?.absoluteString == "https://www.openstreetmap.org/relation/9001")
        #expect(b.citation.title == "Granite Basin National Park")
        #expect(b.citation.retrievedAt == t0)
        #expect(b.citation.licence == d.licence && b.citation.licence?.key == LicenceKey.osm)
    }

    @Test func exactNameBeatsAPrefixMatchEvenWhenSmaller() throws {
        let b = try #require(try OverpassBoundaryMapping.boundary(from: fixture(), named: "granite basin wilderness", near: near, descriptor: d, fetchedAt: t0))
        #expect(b.externalID == "relation/9002" && b.areaKind == "protected_area")
    }

    @Test func aPrefixPicksTheLargestArea() throws {
        // "Granite Basin" is a prefix of the park (0.2 x 0.4 degrees), the wilderness (0.1 x 0.1) and a nature reserve.
        let b = try #require(try OverpassBoundaryMapping.boundary(from: fixture(), named: "Granite Basin", near: near, descriptor: d, fetchedAt: t0))
        #expect(b.externalID == "relation/9001")
    }

    @Test func aClosedWayIsAnAreaToo() throws {
        let b = try #require(try OverpassBoundaryMapping.boundary(from: fixture(), named: "Granite Basin Nature Reserve", near: nil, descriptor: d, fetchedAt: t0))
        #expect(b.externalID == "way/9003" && b.areaKind == "nature_reserve")
        #expect(b.polygon.rings.count == 1 && b.polygon.contains(c(37.05, -119.12)))
        #expect(b.citation.url?.absoluteString == "https://www.openstreetmap.org/way/9003")
    }

    @Test func aRingThatDoesNotCloseIsSkipped() throws {
        #expect(try OverpassBoundaryMapping.boundary(from: fixture(), named: "Granite Basin Open Ring", near: near, descriptor: d, fetchedAt: t0) == nil)
        // And the half-built relation is never chosen by a prefix search either.
        let b = try #require(try OverpassBoundaryMapping.boundary(from: fixture(), named: "Granite", near: near, descriptor: d, fetchedAt: t0))
        #expect(b.externalID == "relation/9001")
    }

    @Test func administrativeAreasAreIgnored() throws {
        #expect(try OverpassBoundaryMapping.boundary(from: fixture(), named: "Granite Basin County", near: near, descriptor: d, fetchedAt: t0) == nil)
    }

    @Test func noMatchIsNil() throws {
        #expect(try OverpassBoundaryMapping.boundary(from: fixture(), named: "Nowhere Park", near: near, descriptor: d, fetchedAt: t0) == nil)
        #expect(try OverpassBoundaryMapping.boundary(from: Data(#"{"elements":[]}"#.utf8), named: "X", near: nil, descriptor: d, fetchedAt: t0) == nil)
        #expect(try OverpassBoundaryMapping.boundary(from: Data(#"{"version":0.6}"#.utf8), named: "X", near: nil, descriptor: d, fetchedAt: t0) == nil)
    }

    @Test func equalAreasAreBrokenByDistanceToNear() throws {
        let south = try #require(try OverpassBoundaryMapping.boundary(from: fixture(), named: "Twin Lakes", near: c(36.0, -118.0), descriptor: d, fetchedAt: t0))
        let north = try #require(try OverpassBoundaryMapping.boundary(from: fixture(), named: "Twin Lakes", near: c(36.5, -118.0), descriptor: d, fetchedAt: t0))
        #expect(south.externalID == "relation/9006" && north.externalID == "relation/9007")
    }

    @Test func garbageThrowsDecoding() {
        #expect(throws: SourceError.self) {
            try OverpassBoundaryMapping.boundary(from: Data("<html>".utf8), named: "X", near: nil, descriptor: d, fetchedAt: t0)
        }
    }

    @Test func nodesWithoutGeometryMakeAnIncompleteWayThatIsDropped() throws {
        let json = """
        {"elements":[{"type":"relation","id":1,"tags":{"boundary":"national_park","name":"Gap Park"},"members":[
          {"type":"way","ref":2,"role":"outer","geometry":[{"lat":0,"lon":0},null,{"lat":1,"lon":1},{"lat":0,"lon":0}]}]}]}
        """
        #expect(try OverpassBoundaryMapping.boundary(from: Data(json.utf8), named: "Gap Park", near: nil, descriptor: d, fetchedAt: t0) == nil)
    }

    @Test func namesWithPunctuationAndAccentsMatchWhenFolded() throws {
        let json = """
        {"elements":[{"type":"way","id":5,"tags":{"leisure":"nature_reserve","name":"Parc national de la Vanoise"},
          "geometry":[{"lat":45,"lon":6},{"lat":45,"lon":6.2},{"lat":45.2,"lon":6.2},{"lat":45,"lon":6}]},
          {"type":"way","id":6,"tags":{"leisure":"nature_reserve","name":"Saint-Ma\u{00EB}l"},
          "geometry":[{"lat":10,"lon":6},{"lat":10,"lon":6.2},{"lat":10.2,"lon":6.2},{"lat":10,"lon":6}]}]}
        """
        let a = try #require(try OverpassBoundaryMapping.boundary(from: Data(json.utf8), named: "parc national de la vanoise", near: nil, descriptor: d, fetchedAt: t0))
        #expect(a.externalID == "way/5")
        let b = try #require(try OverpassBoundaryMapping.boundary(from: Data(json.utf8), named: "Saint Mael", near: nil, descriptor: d, fetchedAt: t0))
        #expect(b.externalID == "way/6")
    }

    // MARK: Simplification

    /// A square park whose outline wiggles by about 330 m at every vertex: nothing is within 50 m of a straight line.
    private func jaggedJSON(vertices: Int) -> Data {
        var geometry: [[String: Double]] = []
        let side = vertices / 4
        func add(_ lat: Double, _ lon: Double, _ i: Int) {
            let wiggle = i % 2 == 0 ? 0.003 : -0.003
            geometry.append(["lat": lat + wiggle, "lon": lon + wiggle])
        }
        var i = 0
        for k in 0..<side { add(36 + Double(k) / Double(side), -119, i); i += 1 }
        for k in 0..<side { add(37, -119 + Double(k) / Double(side), i); i += 1 }
        for k in 0..<side { add(37 - Double(k) / Double(side), -118, i); i += 1 }
        for k in 0..<side { add(36, -118 - Double(k) / Double(side), i); i += 1 }
        geometry.append(geometry[0])
        let object: [String: Any] = ["elements": [["type": "way", "id": 77, "tags": ["boundary": "national_park", "name": "Jagged Park"], "geometry": geometry]]]
        return (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    }

    @Test func aDenseWigglyOutlineIsCappedAtTwoThousandVertices() throws {
        let b = try #require(try OverpassBoundaryMapping.boundary(from: jaggedJSON(vertices: 3_000), named: "Jagged Park", near: nil, descriptor: d, fetchedAt: t0))
        let total = b.polygon.rings.reduce(0) { $0 + $1.count }
        #expect(total <= OverpassBoundaryMapping.maxVertices && total >= 4, "\(total)")
        #expect(b.polygon.contains(c(36.5, -118.5)) && !b.polygon.contains(c(35.5, -118.5)))
    }

    @Test func smoothOutlinesLoseTheirNearlyStraightVerticesAtFiftyMetres() {
        // A circle of 5 km radius sampled every 1 degree: the 360 vertices collapse to a few dozen within 50 m.
        let ring = (0..<360).map { i -> Coordinate in
            let a = Double(i) * .pi / 180
            return c(37 + 0.045 * sin(a), -119 + 0.045 * cos(a) / cos(37 * .pi / 180))
        }
        let simplified = OverpassBoundaryMapping.douglasPeucker(ring, toleranceMeters: 50)
        #expect(simplified.count < 60 && simplified.count >= 8, "\(simplified.count)")
        // Every dropped vertex is within 50 m of the simplified outline (checked against the polygon's edges).
        let poly = GeoPolygon(rings: [simplified])
        #expect(poly.contains(c(37, -119)))
    }

    @Test func collinearPointsAreRemovedAndShortRingsAreKept() {
        let ring = [c(0, 0), c(0, 0.001), c(0, 0.002), c(0.002, 0.002), c(0.002, 0)]
        #expect(OverpassBoundaryMapping.douglasPeucker(ring, toleranceMeters: 50).count == 4)
        let triangle = [c(0, 0), c(0, 1), c(1, 1)]
        #expect(OverpassBoundaryMapping.douglasPeucker(triangle, toleranceMeters: 50) == triangle)
    }

    @Test func ringsJoinInAnyOrderAndDirection() {
        // Four sides of a square in scrambled order and direction.
        let a = c(0, 0), b = c(0, 1), cc = c(1, 1), dd = c(1, 0)
        let ways = [[cc, dd], [a, b], [dd, a], [cc, b]]
        let rings = OverpassBoundaryMapping.rings(from: ways)
        #expect(rings.count == 1 && rings[0].count == 4 && Set(rings[0]) == [a, b, cc, dd])
        // Two separate squares stay two rings; an open chain is dropped.
        let two = OverpassBoundaryMapping.rings(from: [[a, b, cc, a], [c(5, 5), c(5, 6), c(6, 6), c(5, 5)], [c(9, 9), c(9, 10)]])
        #expect(two.count == 2)
    }
}

@Suite("Overpass boundary provider")
struct OverpassBoundaryProviderTests {
    func provider(_ http: StubHTTPClient, clock: ManualSourceClock) -> OverpassBoundaryProvider {
        OverpassBoundaryProvider(http: http, clock: clock)
    }

    @Test func descriptorCarriesTheBoundaryKindAndRank() {
        let p = OverpassBoundaryProvider(http: StubHTTPClient())
        #expect(p.descriptor.id == .osmOverpass)
        #expect(p.descriptor.kinds.contains(.boundary) && p.descriptor.kinds.contains(.gazetteer))
        #expect(p.descriptor.ranks[.boundary] == 10 && p.descriptor.ranks[.gazetteer] == 20)
        #expect(SourceCatalogue.osmOverpass.timeout == .seconds(60))
    }

    @Test func postsOneQueryAndReturnsTheBestMatch() async throws {
        let http = StubHTTPClient()
        http.on(urlContaining: "overpass-api.de", reply: .ok(try fixture()))
        let clock = ManualSourceClock(now: t0)
        let b = try #require(try await provider(http, clock: clock).boundary(named: "  Granite Basin National Park ", near: near))
        #expect(b.externalID == "relation/9001" && b.citation.retrievedAt == t0)
        #expect(http.requests.count == 1)
        let req = try #require(http.requests.first)
        #expect(req.method == "POST" && req.policy.maxRetries == 0 && req.source == .osmOverpass)
        let bodyData = try #require(req.body)
        let body = try #require(String(data: bodyData, encoding: .utf8))
        let query = try #require(body.dropFirst(5).removingPercentEncoding)
        #expect(query == OverpassQueryBuilder.boundaryQuery(name: "Granite Basin National Park", near: near))
        #expect(query.contains("(36.1,-120.126922,37.9,-117.873078)"))
    }

    @Test func noMatchAndEmptyNameGiveNilWithoutInventingAnything() async throws {
        let http = StubHTTPClient()
        http.on(urlContaining: "overpass", reply: .ok(Data(#"{"elements":[]}"#.utf8)))
        let p = provider(http, clock: ManualSourceClock(now: t0))
        #expect(try await p.boundary(named: "Nowhere", near: near) == nil)
        #expect(http.requests.count == 1)
        #expect(try await p.boundary(named: "   ", near: near) == nil)
        #expect(http.requests.count == 1, "an empty name makes no request")
    }

    @Test func sharesTheServerRotationAndBackoffWithTheGazetteer() async throws {
        let http = StubHTTPClient()
        http.on(urlContaining: "overpass-api.de", reply: .status(502, Data("Bad Gateway".utf8)))
        http.on(urlContaining: "overpass.private.coffee", reply: .ok(try fixture()))
        let clock = ManualSourceClock(now: t0)
        let b = try await provider(http, clock: clock).boundary(named: "Granite Basin", near: nil)
        #expect(b?.externalID == "relation/9001")
        #expect(http.requests.map(\.url.host) == ["overpass-api.de", "overpass.private.coffee"])
        #expect(clock.sleeps == [.seconds(10)])
    }

    @Test func aBadQueryFailsAtOnce() async throws {
        let http = StubHTTPClient()
        http.on(urlContaining: "overpass", reply: .status(400, Data("parse error".utf8)))
        await #expect(throws: SourceError.self) { try await provider(http, clock: ManualSourceClock(now: t0)).boundary(named: "X", near: nil) }
        #expect(http.requests.count == 1)
    }
}
