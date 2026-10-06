import Foundation
import Testing
import IterCore
import IterData
import IterServices
@testable import IterFeatures

// Live, view-model-level check. Gated on ITER_LIVE=1 and a key in the process environment (ITER_OPENWEATHER_KEY).
// The key store is in memory, so the Keychain is never touched. Nothing here prints the key or a URL.

private let liveEnabled = ProcessInfo.processInfo.environment["ITER_LIVE"] == "1"
private let envKeyPresent = !(ProcessInfo.processInfo.environment["ITER_OPENWEATHER_KEY"] ?? "")
    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

private struct NoSearch: PlaceSearching, Geocoding, DriveTimeProviding {
    func search(_ query: String, near region: GeoRegion?) async throws -> [PlaceResult] { [] }
    func pointsOfInterest(near center: Coordinate, radiusMeters: Double, categories: [String]) async throws -> [PlaceResult] { [] }
    func reverseGeocode(_ coordinate: Coordinate) async throws -> PlaceResult { throw CancellationError() }
    func geocode(_ query: String) async throws -> [PlaceResult] { [] }
    func drive(from a: Coordinate, to b: Coordinate) async throws -> DriveLeg { .estimate(from: a, to: b) }
}

@MainActor
@Suite("Weather live view model", .serialized) struct WeatherLiveViewModelTests {
    @Test(.enabled(if: liveEnabled && envKeyPresent, "ITER_LIVE=1 and ITER_OPENWEATHER_KEY in the environment"))
    func openWeatherThroughSetupAndSpotModel() async throws {
        let defaults = UserDefaults(suiteName: "iter.tests.weatherlive." + UUID().uuidString)!
        let setup = WeatherSetup(keyStore: InMemoryAPIKeyStore(), cacheDirectory: nil, defaults: defaults,
                                 transport: URLSessionTransport(),
                                 environment: { ProcessInfo.processInfo.environment },
                                 launchArgument: { _ in nil }, apple: nil)
        setup.selectPrimary(.openWeather)
        await setup.settled()

        await setup.check(.openWeather)
        let status = setup.status(for: .openWeather)
        print("OpenWeather status: \(status)")
        guard case .working = status else {
            Issue.record("expected .working, got \(status)")
            return
        }

        let store = IterStore(container: try IterSchema.makeContainer(inMemory: true))
        let none = NoSearch()
        let app = AppModel(store: store, weather: setup.router, search: none, geocoder: none, drives: none, scout: nil,
                           weatherSetup: setup, defaults: defaults)
        let spot = try #require(CuratedSpots.spot(id: "mesa-arch"))
        let model = SpotModel(app: app, spot: spot)
        await model.start()

        let forecast = try #require(model.forecast, "no forecast reached the spot model")
        #expect(forecast.source == .openWeather)
        let windows = model.dayLight.windows
        print("mesa-arch \(model.day): \(windows.map { w in "\(w.kind.rawValue) score=\(w.score.map(String.init) ?? "none") confidence=\(w.assessment.lightScore?.confidence.rawValue ?? "n/a")" }.joined(separator: " | "))")
        let scored = windows.compactMap(\.assessment.lightScore)
        #expect(!scored.isEmpty)
        #expect(scored.allSatisfy { !$0.contributors.isEmpty })
    }
}
