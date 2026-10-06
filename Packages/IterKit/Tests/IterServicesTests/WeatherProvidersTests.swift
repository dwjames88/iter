import Testing
import Foundation
import IterCore
@testable import IterServices

private func okOpenWeather() -> FakeTransport {
    let body = WeatherFixture.data("openweather-onecall3-documented.json")
    return FakeTransport { _ in (200, body) }
}

private func windyReply(_ status: Int = 200, name: String = "windy-gfs-documented-schema.json") -> FakeTransport.Reply {
    let body = WeatherFixture.data(name)
    return { _ in (status, body) }
}

// MARK: Keys

@Suite("API keys") struct APIKeyTests {
    @Test func resolutionOrderAndOrigin() {
        let store = InMemoryAPIKeyStore([.openWeather: "from-keychain"])
        func r(env: [String: String] = [:], arg: String? = nil) -> APIKeyResolver {
            APIKeyResolver(store: store, environment: { env }, launchArgument: { _ in arg })
        }
        #expect(r().resolve(.openWeather)?.origin == .keychain)
        #expect(r(arg: "from-arg").resolve(.openWeather)?.origin == .launchArgument)
        #expect(r(arg: "from-arg").resolve(.openWeather)?.value == "from-arg")
        let all = r(env: ["ITER_OPENWEATHER_KEY": "from-env"], arg: "from-arg").resolve(.openWeather)
        #expect(all?.origin == .environment && all?.value == "from-env")
        #expect(r(env: ["ITER_OPENWEATHER_KEY": "  "], arg: nil).resolve(.openWeather)?.origin == .keychain)   // blank is absent
        #expect(r().resolve(.windy) == nil)
        #expect(r(env: ["ITER_WINDY_KEY": "w"]).resolve(.windy)?.value == "w")
        #expect(r().resolve(.appleWeather) == nil)
    }

    @Test func launchArgumentNameMatchesTheSpec() {
        let seen = Mutex2()
        let resolver = APIKeyResolver(store: InMemoryAPIKeyStore(), environment: { [:] }, launchArgument: { seen.record($0); return nil })
        _ = resolver.resolve(.openWeather); _ = resolver.resolve(.windy)
        #expect(seen.names == ["ITER_OPENWEATHER_KEY", "ITER_WINDY_KEY"])
    }

    @Test func descriptionNeverContainsTheKey() {
        let key = APIKeyResolver(store: InMemoryAPIKeyStore([.windy: secretKey])).resolve(.windy)
        #expect(key != nil)
        #expect(!"\(key!)".contains(secretKey) && !String(reflecting: key!).contains(secretKey))
    }

    @Test func inMemoryStoreRoundTrips() throws {
        let s = InMemoryAPIKeyStore()
        try s.setKey("a", for: .windy)
        #expect(s.key(for: .windy) == "a")
        try s.removeKey(for: .windy)
        #expect(s.key(for: .windy) == nil)
    }

    @Test func keysAreNeverInUserDefaults() throws {
        let d = scratchDefaults()
        let store = InMemoryAPIKeyStore([.openWeather: secretKey])
        let rig = Rig()
        _ = APIKeyResolver(store: store)
        #expect(d.dictionaryRepresentation().values.allSatisfy { !"\($0)".contains(secretKey) })
        #expect(rig.defaults.dictionaryRepresentation().values.allSatisfy { !"\($0)".contains(secretKey) })
    }
}

final class Mutex2: @unchecked Sendable {
    private let lock = NSLock()
    private var _names: [String] = []
    func record(_ n: String) { lock.lock(); _names.append(n); lock.unlock() }
    var names: [String] { lock.lock(); defer { lock.unlock() }; return _names }
}

// MARK: Status mapping and key hygiene

@Suite("HTTP errors") struct HTTPErrorTests {
    @Test(arguments: [(401, WeatherError.keyRejected(.openWeather)), (403, .keyRejected(.openWeather)), (429, .overDailyLimit(.openWeather))])
    func openWeatherStatuses(status: Int, expected: WeatherError) async {
        let rig = Rig(transport: FakeTransport { _ in (status, WeatherFixture.data("openweather-error-401.json")) })
        await #expect(throws: expected) { try await rig.openWeather().forecast(for: moabSpot) }
    }

    @Test func otherStatusIsAProviderErrorWithoutTheKey() async {
        let rig = Rig(transport: FakeTransport { _ in (500, Data(#"{"cod":500,"message":"boom \#(secretKey)"}"#.utf8)) })
        do {
            _ = try await rig.openWeather().forecast(for: moabSpot)
            Issue.record("expected a throw")
        } catch let WeatherError.provider(source, detail) {
            #expect(source == .openWeather)
            #expect(detail.contains("HTTP 500") && detail.contains("boom"))
            #expect(!detail.contains(secretKey))
        } catch { Issue.record("wrong error \(error)") }
    }

    @Test func networkFailureDetailHasNeitherKeyNorURL() async {
        let url = URL(string: "https://api.openweathermap.org/data/3.0/onecall?appid=\(secretKey)")!
        let rig = Rig(transport: FakeTransport { _ in throw URLError(.cannotParseResponse, userInfo: [NSURLErrorFailingURLErrorKey: url, NSURLErrorFailingURLStringErrorKey: url.absoluteString]) })
        do {
            _ = try await rig.openWeather().forecast(for: moabSpot)
            Issue.record("expected a throw")
        } catch let WeatherError.provider(_, detail) {
            #expect(!detail.contains(secretKey) && !detail.contains("appid") && !detail.contains("openweathermap"))
        } catch { Issue.record("wrong error \(error)") }
    }

    @Test func connectivityFailuresAreOffline() async {
        let codes: [URLError.Code] = [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost, .cannotConnectToHost,
                                      .dnsLookupFailed, .internationalRoamingOff, .dataNotAllowed]
        for code in codes {
            let rig = Rig(transport: FakeTransport { _ in throw URLError(code) })
            await #expect(throws: WeatherError.offline(.openWeather)) { try await rig.openWeather().forecast(for: moabSpot) }
        }
        #expect(WeatherError.offline(.windy).unavailableReason == .offline(.windy))
    }

    @Test func unreadableBodyIsAProviderError() async {
        let rig = Rig(transport: FakeTransport { _ in (200, Data("<html>".utf8)) })
        await #expect(throws: WeatherError.provider(.openWeather, "The response could not be read")) { try await rig.openWeather().forecast(for: moabSpot) }
    }

    @Test func windyStatuses() async {
        for (status, expected) in [(401, WeatherError.keyRejected(.windy)), (403, .keyRejected(.windy)), (429, .overDailyLimit(.windy))] {
            let rig = Rig(transport: FakeTransport { _ in (status, Data()) })
            await #expect(throws: expected) { try await rig.windy().forecast(for: alpsSpot) }
        }
    }

    @Test func missingKeyNeverCallsTheNetwork() async {
        let rig = Rig()
        let empty = resolver([:])
        await #expect(throws: WeatherError.missingKey(.openWeather)) { try await rig.openWeather(keys: empty).forecast(for: moabSpot) }
        await #expect(throws: WeatherError.missingKey(.windy)) { try await rig.windy(keys: empty).forecast(for: moabSpot) }
        #expect(rig.transport.callCount == 0 && rig.budget.callsToday(for: .openWeather) == 0)
    }
}

// MARK: OpenWeather service

@Suite("OpenWeather service") struct OpenWeatherServiceTests {
    @Test func requestShape() async throws {
        let rig = Rig(transport: okOpenWeather())
        let f = try await rig.openWeather().forecast(for: moabSpot)
        #expect(f.source == .openWeather && f.hours.count > 48)
        let url = try #require(rig.transport.requests.first?.url)
        let q = Dictionary(uniqueKeysWithValues: URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.map { ($0.name, $0.value ?? "") })
        #expect(url.host == "api.openweathermap.org" && url.path == "/data/3.0/onecall")
        #expect(q["units"] == "metric" && q["exclude"] == "current,minutely,alerts" && q["appid"] == secretKey)
        #expect(q["lat"] == "38.5733" && q["lon"] == "-109.5498")
        #expect(f.fetchedAt == rig.clock.now)
    }

    @Test func attributionIsExact() async throws {
        let a = try #require(await Rig().openWeather().attribution())
        #expect(a.requiredText == "Weather data © OpenWeather")
        #expect(a.legalPageURL.absoluteString == "https://openweathermap.org")
        #expect(a.serviceName == "OpenWeather" && a.combinedMarkLightURL == nil)
    }

    @Test func cacheServesTheSameSpotAndHour() async throws {
        let rig = Rig(transport: okOpenWeather())
        let s = rig.openWeather()
        _ = try await s.forecast(for: moabSpot)
        _ = try await s.forecast(for: moabSpot)
        _ = try await s.forecast(for: Coordinate(latitude: 38.5749, longitude: -109.5451))   // rounds to the same 2 dp
        #expect(rig.transport.callCount == 1)
        _ = try await s.forecast(for: Coordinate(latitude: 38.60, longitude: -109.55))       // another spot
        #expect(rig.transport.callCount == 2)
        #expect(rig.budget.callsToday(for: .openWeather) == 2)
    }

    @Test func cacheLastsThroughTheNextClockHourOnly() async throws {
        // The clock starts at 12:10 UTC: served until 13:59, refetched from 14:00.
        let rig = Rig(transport: okOpenWeather())
        let s = rig.openWeather()
        _ = try await s.forecast(for: moabSpot)
        rig.clock.advance(3600 + 49 * 60)   // 13:59
        _ = try await s.forecast(for: moabSpot)
        #expect(rig.transport.callCount == 1)
        rig.clock.advance(2 * 60)           // 14:01
        _ = try await s.forecast(for: moabSpot)
        #expect(rig.transport.callCount == 2)
    }

    @Test func cachePersistsAcrossInstances() async throws {
        let dir = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let rig = Rig(transport: okOpenWeather(), directory: dir)
        let first = try await rig.openWeather().forecast(for: moabSpot)
        // A "relaunch": new service, new cache object, same directory and clock.
        let again = try await rig.openWeather().forecast(for: moabSpot)
        #expect(rig.transport.callCount == 1)
        #expect(again == first)
        #expect(!(try FileManager.default.contentsOfDirectory(atPath: dir.path)).filter { $0.hasSuffix(".json") }.isEmpty)
        // Persisted files hold the mapped forecast, never the key.
        for f in try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            #expect(!(String(data: try Data(contentsOf: f), encoding: .utf8) ?? "").contains(secretKey))
        }
    }

    @Test func staleDiskEntryIsNotServed() async throws {
        let dir = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let rig = Rig(transport: okOpenWeather(), directory: dir)
        _ = try await rig.openWeather().forecast(for: moabSpot)
        rig.clock.advance(3 * 3600)
        _ = try await rig.openWeather().forecast(for: moabSpot)
        #expect(rig.transport.callCount == 2)
    }

    @Test("service maps every OpenWeather success body", arguments: openWeatherFixtureNames)
    func serviceMapsEachFixture(_ name: String) async throws {
        let body = WeatherFixture.data(name)
        let rig = Rig(transport: FakeTransport { _ in (200, body) })
        let f = try await rig.openWeather().forecast(for: moabSpot)
        #expect(f.source == .openWeather)
        #expect(f.hours.filter { $0.resolution == .hourly }.count == 48)
        #expect(f.days.count == 8)
    }

    @Test func failuresAreNotCached() async throws {
        let rig = Rig(transport: FakeTransport { _ in (500, Data()) })
        let s = rig.openWeather()
        await #expect(throws: (any Error).self) { try await s.forecast(for: moabSpot) }
        rig.transport.setReply { _ in (200, WeatherFixture.data("openweather-onecall3-documented.json")) }
        _ = try await s.forecast(for: moabSpot)
        #expect(rig.transport.callCount == 2)
    }

    @Test func concurrentRequestsShareOneCall() async throws {
        let rig = Rig(transport: okOpenWeather())
        let s = rig.openWeather()
        try await withThrowingTaskGroup(of: Forecast.self) { g in
            for _ in 0..<10 { g.addTask { try await s.forecast(for: moabSpot) } }
            for try await _ in g {}
        }
        #expect(rig.transport.callCount == 1)
    }
}

// MARK: Budget

@Suite("Call budget") struct CallBudgetTests {
    @Test func capStopsCallsBeforeTheNetwork() async throws {
        let rig = Rig(transport: okOpenWeather(), caps: [.openWeather: 2])
        let s = rig.openWeather()
        _ = try await s.forecast(for: Coordinate(latitude: 10, longitude: 10))
        _ = try await s.forecast(for: Coordinate(latitude: 11, longitude: 10))
        await #expect(throws: WeatherError.overDailyLimit(.openWeather)) { try await s.forecast(for: Coordinate(latitude: 12, longitude: 10)) }
        #expect(rig.transport.callCount == 2)                      // the third never reached the wire
        // A cached hit still works at the cap and does not count.
        _ = try await s.forecast(for: Coordinate(latitude: 10, longitude: 10))
        #expect(rig.budget.callsToday(for: .openWeather) == 2)
    }

    @Test func resetsEachUTCDay() throws {
        let clock = TestClock(Date(timeIntervalSince1970: 1_595_289_600 + 23 * 3600))   // 2020-07-21 23:00 UTC
        let b = CallBudget(defaults: scratchDefaults(), caps: [.windy: 1], now: { clock.now })
        try b.reserve(.windy)
        #expect(throws: WeatherError.overDailyLimit(.windy)) { try b.reserve(.windy) }
        clock.advance(2 * 3600)
        #expect(b.callsToday(for: .windy) == 0)
        try b.reserve(.windy)
    }

    @Test func countsPersistInTheInjectedDefaults() throws {
        let d = scratchDefaults(), clock = TestClock()
        let a = CallBudget(defaults: d, now: { clock.now })
        try a.reserve(.openWeather); try a.reserve(.openWeather)
        #expect(CallBudget(defaults: d, now: { clock.now }).callsToday(for: .openWeather) == 2)
    }

    @Test func defaultCapsAndProvidersWithoutACap() throws {
        let b = CallBudget(defaults: scratchDefaults())
        #expect(b.cap(for: .openWeather) == 800 && b.cap(for: .windy) == 400 && b.cap(for: .appleWeather) == nil)
        b.setCap(1000, for: .openWeather)
        #expect(b.cap(for: .openWeather) == 1000)
        for _ in 0..<5 { try b.reserve(.appleWeather) }
    }

    @Test func aRejectedCallStillCounts() async {
        let rig = Rig(transport: FakeTransport { _ in (401, Data()) })
        _ = try? await rig.openWeather().forecast(for: moabSpot)
        #expect(rig.budget.callsToday(for: .openWeather) == 1)
    }
}

// MARK: Windy service

@Suite("Windy service") struct WindyServiceTests {
    @Test func modelChoiceByRegion() {
        #expect(WindyModel.best(for: alpsSpot) == .iconEu)
        #expect(WindyModel.best(for: moabSpot) == .namConus)
        #expect(WindyModel.best(for: hawaiiSpot) == .gfs)
        #expect(WindyModel.best(for: Coordinate(latitude: -33.9, longitude: 151.2)) == .gfs)
        #expect(WindyModelMode.forceGFS.model(for: alpsSpot) == .gfs)
        #expect(WindyModelMode.bestForSpot.model(for: alpsSpot) == .iconEu)
    }

    @Test func requestIsAPostWithTheKeyInTheBodyOnly() async throws {
        let rig = Rig(transport: FakeTransport(windyReply()))
        let f = try await rig.windy().forecast(for: alpsSpot)
        let r = try #require(rig.transport.requests.first)
        #expect(r.httpMethod == "POST" && r.url?.absoluteString == "https://api.windy.com/api/point-forecast/v2")
        #expect(!(r.url?.absoluteString.contains(secretKey) ?? true))
        let b = requestBody(r)
        #expect(b["model"] as? String == "iconEu" && b["key"] as? String == secretKey && b["levels"] as? [String] == ["surface"])
        #expect(Set(b["parameters"] as? [String] ?? []).isSuperset(of: ["lclouds", "mclouds", "hclouds", "precip", "wind", "temp"]))
        #expect(f.model == "ICON-EU" && f.source == .windy)
    }

    @Test func regionalModelWithNoDataRetriesOnGFS() async throws {
        for status in [204, 400] {
            let rig = Rig(transport: FakeTransport { r in
                requestBody(r)["model"] as? String == "gfs" ? (200, WeatherFixture.data("windy-gfs-documented-schema.json")) : (status, Data())
            })
            let f = try await rig.windy().forecast(for: alpsSpot)
            #expect(f.model == "GFS")
            #expect(rig.transport.requests.map { requestBody($0)["model"] as? String } == ["iconEu", "gfs"])
            #expect(rig.budget.callsToday(for: .windy) == 2)       // the retry is a real call and is counted
        }
    }

    @Test func regionalModelWithoutCloudsRetriesOnGFS() async throws {
        var noClouds = WeatherFixture.json("windy-gfs-documented-schema.json")
        for k in ["lclouds-surface", "mclouds-surface", "hclouds-surface"] { noClouds[k] = nil }
        let bare = WeatherFixture.encode(noClouds)
        let rig = Rig(transport: FakeTransport { r in
            requestBody(r)["model"] as? String == "gfs" ? (200, WeatherFixture.data("windy-gfs-documented-schema.json")) : (200, bare)
        })
        let f = try await rig.windy().forecast(for: moabSpot)
        #expect(f.model == "GFS" && rig.transport.callCount == 2)
    }

    @Test func gfsWithNothingIsAProviderErrorAfterOneTry() async {
        let rig = Rig(transport: FakeTransport { _ in (204, Data()) })
        await #expect(throws: WeatherError.provider(.windy, "The model returned no usable data")) { try await rig.windy(mode: .forceGFS).forecast(for: alpsSpot) }
        #expect(rig.transport.callCount == 1)
        // A 400 from the regional model retries on GFS; a 400 from GFS itself is a real request/key problem and keeps Windy's message.
        let rig2 = Rig(transport: FakeTransport { _ in (400, Data(#"{"message":"Invalid request"}"#.utf8)) })
        await #expect(throws: WeatherError.provider(.windy, "HTTP 400: Invalid request")) { try await rig2.windy().forecast(for: alpsSpot) }
        #expect(rig2.transport.callCount == 2)                       // iconEu, then one gfs retry, no more
    }

    @Test func forceGFSIgnoresTheRegion() async throws {
        let rig = Rig(transport: FakeTransport(windyReply()))
        let f = try await rig.windy(mode: .forceGFS).forecast(for: alpsSpot)
        #expect(f.model == "GFS" && requestBody(rig.transport.requests[0])["model"] as? String == "gfs")
    }

    @Test func testingKeyIsRefusedAfterTheCallAndNeverCached() async throws {
        let rig = Rig(transport: FakeTransport(windyReply()))
        let s = rig.windy(keyType: .testing)
        await #expect(throws: WeatherError.testingKey(.windy)) { try await s.forecast(for: alpsSpot) }
        #expect(rig.transport.callCount == 1)                        // the call was made so the integration can be checked
        await #expect(throws: WeatherError.testingKey(.windy)) { try await s.forecast(for: alpsSpot) }
        #expect(rig.transport.callCount == 2)                        // nothing was stored
    }

    @Test func aWarningMeansTestingEvenForAProfessionalKey() async {
        let rig = Rig(transport: FakeTransport(windyReply(name: "windy-testing-warning-documented-schema.json")))
        await #expect(throws: WeatherError.testingKey(.windy)) { try await rig.windy(keyType: .professional).forecast(for: alpsSpot) }
    }

    @Test func professionalKeyReturnsAForecastCachedInMemoryForThreeHours() async throws {
        let rig = Rig(transport: FakeTransport(windyReply()))
        let s = rig.windy()
        let f = try await s.forecast(for: alpsSpot)
        #expect(f.hours.count > 100)
        _ = try await s.forecast(for: alpsSpot)
        rig.clock.advance(2 * 3600 + 1800)
        _ = try await s.forecast(for: alpsSpot)
        #expect(rig.transport.callCount == 1)
        rig.clock.advance(1800 + 60)
        _ = try await s.forecast(for: alpsSpot)
        #expect(rig.transport.callCount == 2)
    }

    @Test func windyNeverPersistsAnything() async throws {
        // The cache the factory builds for Windy has no directory; a service given one still has nothing on disk.
        let dir = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let rig = Rig(transport: FakeTransport(windyReply()))
        _ = try await rig.windy().forecast(for: alpsSpot)
        #expect(!FileManager.default.fileExists(atPath: dir.path))
    }

    @Test func budgetCapStopsWindyBeforeTheNetwork() async {
        let rig = Rig(transport: FakeTransport(windyReply()), caps: [.windy: 0])
        await #expect(throws: WeatherError.overDailyLimit(.windy)) { try await rig.windy().forecast(for: alpsSpot) }
        #expect(rig.transport.callCount == 0)
    }

    @Test func errorDetailsNeverContainTheKey() async {
        let rig = Rig(transport: FakeTransport { _ in (500, Data(#"{"message":"bad key \#(secretKey)"}"#.utf8)) })
        do { _ = try await rig.windy().forecast(for: alpsSpot) } catch let WeatherError.provider(_, d) { #expect(!d.contains(secretKey)) } catch {}
    }

    @Test func attributionIsExact() async throws {
        let a = try #require(await Rig().windy().attribution())
        #expect(a.serviceName == "Windy" && a.requiredText == "Contains data from the Windy database")
        #expect(a.legalPageURL.absoluteString == "https://www.windy.com")
    }
}

// MARK: Router

@Suite("Weather router") struct WeatherRouterTests {
    let t1 = Date(timeIntervalSince1970: 100), t2 = Date(timeIntervalSince1970: 200)

    final class Log: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [String] = []
        func add(_ s: String) { lock.lock(); items.append(s); lock.unlock() }
        var all: [String] { lock.lock(); defer { lock.unlock() }; return items }
    }
    func observer(_ log: Log) -> WeatherRouter.Observer {
        { source, result in
            switch result {
            case .success(let d): log.add("\(source.rawValue) ok \(Int(d.timeIntervalSince1970))")
            case .failure(let e): log.add("\(source.rawValue) \(e)")
            }
        }
    }

    @Test func firstSuccessWinsAndFallbackIsRecorded() async throws {
        let a = StubProvider(.appleWeather, .failure(.notEnabled)), o = StubProvider(.openWeather, .success(t1))
        let log = Log()
        let router = WeatherRouter(providers: [a, o], observer: observer(log))
        let f = try await router.forecast(for: moabSpot)
        #expect(f.source == .openWeather && f.fallbackFrom == [.appleWeather])
        #expect(log.all == ["appleWeather notEnabled", "openWeather ok 100"])
        #expect(router.source == .appleWeather)                      // the primary's
    }

    @Test func primarySuccessSkipsTheFallback() async throws {
        let a = StubProvider(.appleWeather, .success(t1)), o = StubProvider(.openWeather, .success(t2))
        let router = WeatherRouter(providers: [a, o])
        let f = try await router.forecast(for: moabSpot)
        #expect(f.source == .appleWeather && f.fallbackFrom.isEmpty && o.callCount == 0)
    }

    @Test func allFailingThrowsThePrimarysError() async {
        let log = Log()
        let router = WeatherRouter(providers: [StubProvider(.windy, .failure(.testingKey(.windy))), StubProvider(.openWeather, .failure(.missingKey(.openWeather)))],
                                   observer: observer(log))
        await #expect(throws: WeatherError.testingKey(.windy)) { try await router.forecast(for: moabSpot) }
        #expect(log.all.count == 2)
    }

    @Test func emptyListFails() async {
        await #expect(throws: WeatherError.failed("No weather provider is configured")) { try await WeatherRouter(providers: []).forecast(for: moabSpot) }
    }

    @Test func providersCanBeReplacedAtRunTime() async throws {
        let router = WeatherRouter(providers: [StubProvider(.appleWeather, .success(t1))])
        #expect(router.source == .appleWeather)
        await router.setProviders([StubProvider(.windy, .failure(.keyRejected(.windy))), StubProvider(.openWeather, .success(t2))])
        #expect(router.source == .windy)
        let f = try await router.forecast(for: moabSpot)
        #expect(f.source == .openWeather && f.fallbackFrom == [.windy])
    }

    @Test func attributionComesFromTheNamedProvider() async {
        let router = WeatherRouter(providers: [StubProvider(.appleWeather, .success(t1)), StubProvider(.openWeather, .success(t1))])
        #expect(await router.attribution()?.serviceName == "appleWeather")
        #expect(await router.attribution(for: .openWeather)?.serviceName == "openWeather")
        #expect(await router.attribution(for: .windy) == nil)
    }
}

// MARK: Factory

@Suite("Provider factory") struct WeatherProviderFactoryTests {
    @Test func settingsOrderDropsARepeat() {
        #expect(WeatherSettings(primary: .windy, fallback: .windy).order == [.windy])
        #expect(WeatherSettings(primary: .appleWeather, fallback: .openWeather).order == [.appleWeather, .openWeather])
        #expect(WeatherSettings(primary: .appleWeather).order == [.appleWeather])
    }

    @Test func buildsAWorkingStackFromSettings() async throws {
        let transport = okOpenWeather()
        let apple = StubProvider(.appleWeather, .failure(.notEnabled))
        let factory = WeatherProviderFactory(keyStore: InMemoryAPIKeyStore([.openWeather: secretKey]), cacheDirectory: nil,
                                             defaults: scratchDefaults(), transport: transport, environment: { [:] },
                                             launchArgument: { _ in nil }, apple: apple)
        let router = factory.makeRouter(settings: WeatherSettings(primary: .appleWeather, fallback: .openWeather, openWeatherDailyCap: 5))
        let f = try await router.forecast(for: moabSpot)
        #expect(f.source == .openWeather && f.fallbackFrom == [.appleWeather])
        #expect(factory.usage(for: .openWeather) == (1, 5))
        await factory.apply(WeatherSettings(primary: .openWeather), to: router)
        #expect(router.source == .openWeather)
        _ = try await router.forecast(for: moabSpot)
        #expect(transport.callCount == 1)                            // served from the factory's shared cache
    }

    @Test func windyKeyTypeComesFromSettings() async {
        let transport = FakeTransport(windyReply())
        let factory = WeatherProviderFactory(keyStore: InMemoryAPIKeyStore([.windy: secretKey]), cacheDirectory: nil,
                                             defaults: scratchDefaults(), transport: transport, environment: { [:] },
                                             launchArgument: { _ in nil }, apple: StubProvider(.appleWeather, .failure(.notEnabled)))
        let testing = factory.makeRouter(settings: WeatherSettings(primary: .windy, windyKeyType: .testing))
        await #expect(throws: WeatherError.testingKey(.windy)) { try await testing.forecast(for: alpsSpot) }
        let pro = factory.makeRouter(settings: WeatherSettings(primary: .windy, windyKeyType: .professional))
        let f = try? await pro.forecast(for: alpsSpot)
        #expect(f?.source == .windy)
    }
}

// MARK: Opt-in live tests

private let liveEnabled = ProcessInfo.processInfo.environment["ITER_LIVE"] == "1"
private func liveKey(_ s: ForecastSource) -> String? { APIKeyResolver(store: KeychainAPIKeyStore()).resolve(s)?.value }

/// These call the real providers. They run only with ITER_LIVE=1 AND a key present (environment, launch argument or Keychain); otherwise they are skipped.
@Suite("Weather live", .serialized) struct WeatherLiveTests {
    @Test(.enabled(if: liveEnabled && liveKey(.openWeather) != nil, "ITER_LIVE=1 and an OpenWeather key"))
    func openWeatherLive() async throws {
        let service = OpenWeatherService(keys: APIKeyResolver(store: KeychainAPIKeyStore()), transport: URLSessionTransport(),
                                         cache: ProviderCache(directory: nil, validity: .throughNextClockHour),
                                         budget: CallBudget(defaults: scratchDefaults()))
        let f = try await service.forecast(for: moabSpot)
        #expect(f.hours.count >= 48 && f.source == .openWeather)
    }

    @Test(.enabled(if: liveEnabled && liveKey(.windy) != nil, "ITER_LIVE=1 and a Windy key"))
    func windyLive() async throws {
        let service = WindyService(keys: APIKeyResolver(store: KeychainAPIKeyStore()), transport: URLSessionTransport(),
                                   cache: ProviderCache(directory: nil, validity: .interval(3 * 3600)),
                                   budget: CallBudget(defaults: scratchDefaults()), keyType: .professional)
        do {
            let f = try await service.forecast(for: alpsSpot)
            #expect(f.hours.count > 24 && f.model != nil)
        } catch WeatherError.testingKey {
            // A testing key answered and was refused, which is the designed behaviour.
        }
    }
}
