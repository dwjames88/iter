import Foundation
import Testing
import IterModel
import IterSources
@testable import IterSourcesLive

private let whitney = Coordinate(latitude: 36.5785, longitude: -118.2923)
private let gotthard = Coordinate(latitude: 46.5586, longitude: 8.5610)
private let nearEdwards = Coordinate(latitude: 35.0, longitude: -117.8)
/// 2026-11-22T13:45:00Z, ten minutes after KO26's report and 49 minutes after KBIH's.
private let now = Date(timeIntervalSince1970: 1_795_355_100)

private func stubW(taf: StubHTTPClient.Reply? = nil) throws -> StubHTTPClient {
    let stub = StubHTTPClient()
    stub.on(urlContaining: "/metar?", reply: .ok(try Fixtures.data("AviationWeather/metar-W.json")))
    stub.on(urlContaining: "/taf?", reply: taf ?? .ok(try Fixtures.data("AviationWeather/taf-W.txt")))
    return stub
}

private func provider(_ stub: StubHTTPClient) -> AviationWeatherProvider {
    AviationWeatherProvider(http: stub, clock: ManualSourceClock(now: Date(timeIntervalSince1970: 1_795_355_100)))
}

/// `bbox=S,W,N,E` from a request URL.
private func bbox(_ r: SourceRequest) -> [Double] {
    let q = URLComponents(url: r.url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "bbox" }?.value ?? ""
    return q.split(separator: ",").compactMap { Double($0) }
}

@Suite("AviationWeatherProvider")
struct AviationWeatherProviderTests {
    @Test func requestShapes() throws {
        let url = AviationWeatherProvider.metarURL(near: whitney, halfWidthKm: 100)
        #expect(url.absoluteString.hasPrefix("https://aviationweather.gov/api/data/metar?bbox="))
        #expect(url.absoluteString.hasSuffix("&format=json"))
        let b = bbox(SourceRequest.get(url, from: SourceCatalogue.aviationWeather))
        #expect(b.count == 4)
        #expect(abs(b[0] - (36.5785 - 100 / 111.32)) < 0.001)
        #expect(abs(b[2] - (36.5785 + 100 / 111.32)) < 0.001)
        #expect(b[1] < -118.2923 && b[3] > -118.2923)
        #expect(AviationWeatherProvider.tafURL(ids: ["KO26", "KBIH"]).absoluteString
            == "https://aviationweather.gov/api/data/taf?ids=KO26,KBIH&format=raw")
    }

    @Test func nearestReportsWithTAFs() async throws {
        let stub = try stubW()
        let result = try await provider(stub).reports(near: whitney, within: 150, limit: 3)
        // KEDW is 189 km away: outside 150 km even though the stub returns it.
        #expect(result.map(\.value.stationID) == ["KO26", "KBIH", "KNID"])
        #expect(abs(result[0].value.distanceKm - 21.5) < 0.1)
        #expect(result[0].value.rawTAF == nil)  // KO26 has no TAF
        #expect(result[1].value.rawTAF?.hasPrefix("TAF KBIH 221136Z") == true)
        #expect(result[2].value.rawTAF?.hasPrefix("TAF COR KNID") == true)

        #expect(stub.requests.count == 2)
        let metar = stub.requests[0], taf = stub.requests[1]
        #expect(metar.url.path == "/api/data/metar")
        #expect(URLComponents(url: metar.url, resolvingAgainstBaseURL: false)?.queryItems?.map(\.name) == ["bbox", "format"])
        let b = bbox(metar)
        #expect(b[0] < 36.5785 && b[2] > 36.5785 && b[1] < -118.2923 && b[3] > -118.2923)
        #expect(abs((b[2] - b[0]) / 2 * 111.32 - 150) < 0.5)
        #expect(taf.url.absoluteString == "https://aviationweather.gov/api/data/taf?ids=KO26,KBIH,KNID&format=raw")
        #expect(metar.source == .aviationWeather)
        #expect(metar.policy == SourceCatalogue.aviationWeather.policy)
    }

    @Test func limitIsApplied() async throws {
        let stub = try stubW()
        let result = try await provider(stub).reports(near: whitney, within: 150, limit: 1)
        #expect(result.map(\.value.stationID) == ["KO26"])
        #expect(stub.requests[1].url.absoluteString.contains("ids=KO26&"))
    }

    @Test func withinIsClampedTo150Km() async throws {
        let stub = try stubW()
        _ = try await provider(stub).reports(near: whitney, within: 5000, limit: 5)
        let b = bbox(stub.requests[0])
        #expect(abs((b[2] - b[0]) / 2 * 111.32 - 150) < 0.5)
    }

    @Test func provenanceCarriesOriginAndDistance() async throws {
        let stub = try stubW()
        let result = try await provider(stub).reports(near: nearEdwards, within: 100, limit: 3)
        #expect(result.map(\.value.stationID) == ["KEDW", "KNID"])  // KBIH and KO26 are farther than 100 km
        let edw = result[0]
        #expect(edw.value.isMilitary)
        #expect(edw.provenance.origin?.tier == .military)
        #expect(edw.provenance.origin?.distributor == "NOAA Aviation Weather Center")
        #expect(edw.provenance.origin?.label.hasPrefix("Military-origin") == true)
        #expect(abs(edw.provenance.distanceKm! - 12.25) < 0.05)
        #expect(edw.provenance.issuedAt == edw.value.observedAt)
        #expect(edw.provenance.fetchedAt == now)
        #expect(edw.provenance.source == .aviationWeather)
        #expect(edw.provenance.url?.absoluteString == "https://aviationweather.gov/data/metar/?ids=KEDW")

        let civil = try await provider(try stubW()).reports(near: whitney, within: 150, limit: 1)
        #expect(civil[0].provenance.origin?.tier == .government)
        #expect(civil[0].provenance.origin?.label.hasPrefix("Government") == true)
    }

    @Test func swissMilitaryOrigin() async throws {
        let stub = StubHTTPClient()
        stub.on(urlContaining: "/metar?", reply: .ok(try Fixtures.data("AviationWeather/metar-S.json")))
        stub.on(urlContaining: "/taf?", reply: .ok(try Fixtures.data("AviationWeather/taf-S.txt")))
        let result = try await provider(stub).reports(near: gotthard, within: 70, limit: 10)
        #expect(result.map(\.value.stationID) == ["LSMM", "LSMA", "LSZC", "LSZL", "LSME", "LSZA"])
        let meiringen = result[0]
        #expect(meiringen.value.stationName == "Meiringen Arpt, BE, CH")
        #expect(meiringen.value.isMilitary)
        #expect(meiringen.provenance.origin?.tier == .military)
        #expect(result.first { $0.value.stationID == "LSME" }?.value.isMilitary == true)
        #expect(result.first { $0.value.stationID == "LSZL" }?.value.isMilitary == false)
        #expect(result.first { $0.value.stationID == "LSZC" }?.provenance.origin?.tier == .government)
        #expect(meiringen.value.rawTAF != nil)
    }

    @Test func widensOnceWhenTheBoxIsEmpty() async throws {
        let stub = StubHTTPClient()
        stub.on(urlContaining: "/metar?", reply: .ok(Data("[]".utf8)), .ok(try Fixtures.data("AviationWeather/metar-bbox-W.json")))
        stub.on(urlContaining: "/taf?", reply: .ok(try Fixtures.data("AviationWeather/taf-W.txt")))
        let result = try await provider(stub).reports(near: whitney, within: 20, limit: 3)
        #expect(result.map(\.value.stationID) == ["KO26"])
        let metars = stub.requests.filter { $0.url.path.hasSuffix("/metar") }
        #expect(metars.count == 2)
        let first = bbox(metars[0]), second = bbox(metars[1])
        #expect(abs((second[2] - second[0]) / (first[2] - first[0]) - 2) < 0.01)
    }

    @Test func givesUpAfterOneWidening() async throws {
        let stub = StubHTTPClient()
        stub.on(urlContaining: "/metar?", reply: .ok(Data()))
        let result = try await provider(stub).reports(near: whitney, within: 20, limit: 3)
        #expect(result.isEmpty)
        #expect(stub.requests.count == 2)  // two METAR requests, no TAF request
    }

    @Test func noContentIsEmpty() async throws {
        let stub = StubHTTPClient()
        stub.on(urlContaining: "/metar?", reply: .status(204))
        #expect(try await provider(stub).reports(near: whitney, within: 50, limit: 3).isEmpty)
    }

    @Test func failedTAFLeavesReportsIntact() async throws {
        let stub = try stubW(taf: .status(500, Data("oops".utf8)))
        let result = try await provider(stub).reports(near: whitney, within: 150, limit: 3)
        #expect(result.count == 3)
        #expect(result.allSatisfy { $0.value.rawTAF == nil })
    }

    @Test func metarErrorsAreSourceErrors() async throws {
        let offline = StubHTTPClient()
        offline.on(urlContaining: "/metar?", reply: .error(.offline))
        await #expect(throws: SourceError.offline) { try await provider(offline).reports(near: whitney, within: 50, limit: 3) }
        let bad = StubHTTPClient()
        bad.on(urlContaining: "/metar?", reply: .ok(Data("<html>nope</html>".utf8)))
        await #expect(throws: SourceError.self) { try await provider(bad).reports(near: whitney, within: 50, limit: 3) }
        let none = StubHTTPClient()
        await #expect(throws: SourceError.self) { try await provider(none).reports(near: Coordinate(latitude: 100, longitude: 0), within: 50, limit: 3) }
        #expect(none.requests.isEmpty)
    }

    // MARK: ObservationProvider

    @Test func latestFiltersByAgeNearestFirst() async throws {
        let stub = try stubW()
        let fresh = try await provider(stub).latest(near: whitney, within: 150, maxAge: .seconds(30 * 60))
        #expect(fresh.map(\.value.stationName) == ["Lone Pine Arpt, CA, US"])
        #expect(stub.requests.allSatisfy { $0.url.path.hasSuffix("/metar") })  // observations need no TAF

        let wider = try await provider(try stubW()).latest(near: whitney, within: 150, maxAge: .seconds(2 * 3600))
        #expect(wider.map(\.value.stationName) == ["Lone Pine Arpt, CA, US", "Bishop Rgnl, CA, US", "China Lake , CA, US"])
        #expect(wider.map { $0.provenance.distanceKm!.rounded() } == [21, 88, 113])
        #expect(wider[0].provenance.issuedAt == Date(timeIntervalSince1970: 1_795_354_500))
        #expect(wider[0].provenance.fetchedAt == now)
        #expect(wider[2].provenance.origin?.tier == .military)  // KNID
        #expect(wider[2].value.conditions.presentFields.isEmpty)  // partial report, no zeros
        #expect(wider[1].value.conditions.cloudBaseM != nil)
    }

    @Test func latestUsesTheInjectedClock() async throws {
        let clock = ManualSourceClock(now: Date(timeIntervalSince1970: 1_795_355_100))
        let p = AviationWeatherProvider(http: try stubW(), clock: clock)
        #expect(try await p.latest(near: whitney, within: 150, maxAge: .seconds(30 * 60)).count == 1)
        clock.advance(by: .seconds(3600))  // KO26 is now 70 minutes old
        #expect(try await p.latest(near: whitney, within: 150, maxAge: .seconds(30 * 60)).isEmpty)
    }

    @Test func descriptorIsTheCatalogues() {
        let p = provider(StubHTTPClient())
        #expect(p.descriptor == SourceCatalogue.aviationWeather)
        #expect(p.descriptor.kinds == [.observation])
    }
}
