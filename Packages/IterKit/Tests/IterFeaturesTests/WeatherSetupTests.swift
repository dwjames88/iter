import Foundation
import Testing
import IterCore
import IterData
import IterServices
@testable import IterFeatures

private struct StubTransport: HTTPTransport {
    var status: Int
    var body = Data(#"{"cod":401,"message":"Invalid API key"}"#.utf8)
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        (body, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!)
    }
}

private struct StubApple: WeatherProviding {
    var result: Result<Date, WeatherError>
    var source: ForecastSource { .appleWeather }
    func forecast(for coordinate: Coordinate) async throws -> Forecast {
        switch result {
        case .success(let date): Forecast(coordinate: coordinate, hours: [], days: [], fetchedAt: date, source: .appleWeather)
        case .failure(let error): throw error
        }
    }
    func attribution() async -> WeatherAttributionInfo? { nil }
}

private struct SetupNoSearch: PlaceSearching, Geocoding, DriveTimeProviding {
    func search(_ query: String, near region: GeoRegion?) async throws -> [PlaceResult] { [] }
    func pointsOfInterest(near center: Coordinate, radiusMeters: Double, categories: [String]) async throws -> [PlaceResult] { [] }
    func reverseGeocode(_ coordinate: Coordinate) async throws -> PlaceResult { throw CancellationError() }
    func geocode(_ query: String) async throws -> [PlaceResult] { [] }
    func drive(from a: Coordinate, to b: Coordinate) async throws -> DriveLeg { .estimate(from: a, to: b) }
}

private func scratch() -> UserDefaults { UserDefaults(suiteName: "iter.tests.weathersetup." + UUID().uuidString)! }

@MainActor
@Suite struct WeatherSetupTests {
    nonisolated static let when = Date(timeIntervalSince1970: 1_790_000_000)

    func setup(defaults: UserDefaults = scratch(), keys: InMemoryAPIKeyStore = InMemoryAPIKeyStore(), status: Int = 401,
               apple: Result<Date, WeatherError> = .failure(.notEnabled),
               environment: [String: String] = [:]) -> WeatherSetup {
        WeatherSetup(keyStore: keys, cacheDirectory: nil, defaults: defaults, transport: StubTransport(status: status),
                     environment: { environment }, launchArgument: { _ in nil }, apple: StubApple(result: apple), now: { Self.when })
    }

    @Test func choicesPersistAndNoKeyEverReachesDefaults() async throws {
        let defaults = scratch()
        let keys = InMemoryAPIKeyStore()
        let a = setup(defaults: defaults, keys: keys)
        a.selectPrimary(.openWeather)
        a.selectFallback(.appleWeather)
        a.setWindyKeyType(.professional)
        a.setWindyModelMode(.forceGFS)
        a.setCap(250, for: .openWeather)
        a.setCap(120, for: .windy)
        try a.setKey("SECRET-KEY-123", for: .openWeather)
        await a.settled()

        let b = setup(defaults: defaults, keys: keys)
        #expect(b.settings.primary == .openWeather)
        #expect(b.settings.fallback == .appleWeather)
        #expect(b.settings.windyKeyType == .professional)
        #expect(b.settings.windyModelMode == .forceGFS)
        #expect(b.settings.openWeatherDailyCap == 250)
        #expect(b.settings.windyDailyCap == 120)
        let dump = String(describing: defaults.dictionaryRepresentation())
        #expect(!dump.contains("SECRET-KEY-123"))
    }

    @Test func primaryAndFallbackNeverMatch() async {
        let s = setup()
        s.selectFallback(.windy)
        s.selectPrimary(.windy)
        #expect(s.settings.primary == .windy)
        #expect(s.settings.fallback == nil)
        s.selectFallback(.windy)
        #expect(s.settings.fallback == nil)
        s.selectPrimary(.sample)
        #expect(s.settings.primary == .windy)
        await s.settled()
    }

    @Test func keysGoToTheStoreAndShowOnlyTheirOrigin() async throws {
        let keys = InMemoryAPIKeyStore()
        let s = setup(keys: keys)
        #expect(s.status(for: .openWeather) == .needsKey)
        try s.setKey("  abc123  ", for: .openWeather)
        #expect(keys.key(for: .openWeather) == "abc123")
        #expect(s.keyOrigin(for: .openWeather) == .keychain)
        await s.settled()
        try s.removeKey(for: .openWeather)
        #expect(keys.key(for: .openWeather) == nil)
        #expect(s.status(for: .openWeather) == .needsKey)
        try s.setKey("   ", for: .windy)
        #expect(keys.key(for: .windy) == nil)
        await s.settled()
    }

    @Test func anEnvironmentKeyOverridesTheKeychain() {
        let s = setup(keys: InMemoryAPIKeyStore([.openWeather: "stored"]), environment: ["ITER_OPENWEATHER_KEY": "from-env"])
        #expect(s.keyOrigin(for: .openWeather) == .environment)
    }

    @Test func statusMapsEachObserverResult() {
        let s = setup(keys: InMemoryAPIKeyStore([.openWeather: "k", .windy: "w"]))
        s.setWindyKeyType(.professional)
        #expect(s.status(for: .openWeather) == .notChecked)
        s.record(.openWeather, .success(Self.when))
        #expect(s.status(for: .openWeather) == .working(lastUpdate: Self.when))
        s.record(.openWeather, .failure(.keyRejected(.openWeather)))
        #expect(s.status(for: .openWeather) == .keyRejected)
        s.record(.openWeather, .failure(.provider(.openWeather, "HTTP 500")))
        #expect(s.status(for: .openWeather) == .failed(detail: "HTTP 500"))
        s.record(.openWeather, .success(Self.when))
        #expect(s.lastError[.openWeather] == nil)

        s.record(.windy, .failure(.testingKey(.windy)))
        #expect(s.status(for: .windy) == .testingKey)
        s.record(.windy, .failure(.overDailyLimit(.windy)))
        #expect(s.status(for: .windy) == .dailyCap(calls: 0, cap: 400))
        s.record(.appleWeather, .failure(.notEnabled))
        #expect(s.status(for: .appleWeather) == .notEnabled)
        s.record(.appleWeather, .success(Self.when))
        #expect(s.status(for: .appleWeather) == .working(lastUpdate: Self.when))
    }

    @Test func aTestingWindyKeyShowsAsTestingBeforeAnyCall() {
        let s = setup(keys: InMemoryAPIKeyStore([.windy: "w"]))
        #expect(s.settings.windyKeyType == .testing)
        #expect(s.status(for: .windy) == .testingKey)
    }

    @Test func checkProbesOneProviderWithoutChangingTheSelection() async {
        let s = setup(keys: InMemoryAPIKeyStore([.openWeather: "k"]), status: 401, apple: .success(Self.when))
        await s.check(.openWeather)
        #expect(s.status(for: .openWeather) == .keyRejected)
        await s.check(.appleWeather)
        #expect(s.status(for: .appleWeather) == .working(lastUpdate: Self.when))
        #expect(s.settings.primary == .appleWeather)
        #expect(s.settings.fallback == nil)
        #expect(s.checking.isEmpty)
    }

    @Test func theRouterTriesPrimaryThenFallbackAndTheObserverFeedsStatus() async throws {
        let s = setup(keys: InMemoryAPIKeyStore([.openWeather: "k"]), status: 401, apple: .success(Self.when))
        s.selectPrimary(.openWeather)
        s.selectFallback(.appleWeather)
        await s.settled()
        let forecast = try await s.router.forecast(for: WeatherSetup.probeCoordinate)
        #expect(forecast.source == .appleWeather)
        #expect(forecast.fallbackFrom == [.openWeather])
        for _ in 0..<200 where s.status(for: .openWeather) != .keyRejected { await Task.yield(); try await Task.sleep(for: .milliseconds(5)) }
        #expect(s.status(for: .openWeather) == .keyRejected)
        #expect(s.status(for: .appleWeather) == .working(lastUpdate: Self.when))
    }

    @Test func changingSettingsDropsForecastStatesAndRefetches() async throws {
        let defaults = scratch()
        defaults.set(false, forKey: AppModel.sampleDataKey)
        let store = IterStore(container: try IterSchema.makeContainer(inMemory: true))
        let weather = setup(defaults: defaults, apple: .success(Self.when))
        let model = AppModel(store: store, weather: StubApple(result: .success(Self.when)), search: SetupNoSearch(), geocoder: SetupNoSearch(),
                             drives: SetupNoSearch(), scout: nil, weatherSetup: weather, defaults: defaults)
        let spot = try #require(CuratedSpots.spot(id: "mesa-arch"))
        _ = await model.forecasts.load(spot.coordinate)
        #expect(model.forecasts.states.count == 1)
        let before = model.forecasts.revision
        weather.setCap(100, for: .openWeather)
        await weather.settled()
        #expect(model.forecasts.states.isEmpty)
        #expect(model.forecasts.revision > before)
        _ = await model.forecasts.load(spot.coordinate)
        #expect(model.forecasts.states.count == 1)
    }

    @Test func attributionsLoadForEverySelectableSource() async throws {
        let store = IterStore(container: try IterSchema.makeContainer(inMemory: true))
        let model = AppModel(store: store, weather: StubApple(result: .success(Self.when)), search: SetupNoSearch(), geocoder: SetupNoSearch(),
                             drives: SetupNoSearch(), scout: nil, defaults: scratch())
        await model.loadAttribution()
        #expect(model.attribution(for: .openWeather)?.requiredText != nil)
        #expect(model.attribution(for: .windy) != nil)
    }
}
