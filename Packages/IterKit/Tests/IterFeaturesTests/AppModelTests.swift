import Foundation
import Testing
import IterCore
import IterAstro
import IterData
import IterServices
@testable import IterFeatures

private struct NotEnabledWeather: WeatherProviding {
    var source: ForecastSource { .appleWeather }
    func forecast(for coordinate: Coordinate) async throws -> Forecast { throw WeatherError.notEnabled }
    func attribution() async -> WeatherAttributionInfo? { nil }
}

private struct NoSearch: PlaceSearching, Geocoding, DriveTimeProviding {
    func search(_ query: String, near region: GeoRegion?) async throws -> [PlaceResult] { [] }
    func pointsOfInterest(near center: Coordinate, radiusMeters: Double, categories: [String]) async throws -> [PlaceResult] { [] }
    func reverseGeocode(_ coordinate: Coordinate) async throws -> PlaceResult { throw CancellationError() }
    func geocode(_ query: String) async throws -> [PlaceResult] { [] }
    func drive(from a: Coordinate, to b: Coordinate) async throws -> DriveLeg { .estimate(from: a, to: b) }
}

@MainActor
@Suite struct AppModelTests {
    static let now = LocalDay(year: 2026, month: 10, day: 6).at(hour: 10, in: TimeZone(identifier: "America/Denver")!)

    func model(sampleOn: Bool) throws -> AppModel {
        let defaults = UserDefaults(suiteName: "AppModelTests-\(UUID().uuidString)")!
        defaults.set(sampleOn, forKey: AppModel.sampleDataKey)
        let store = IterStore(container: try IterSchema.makeContainer(inMemory: true))
        let fixed = Self.now
        return AppModel(store: store, weather: NotEnabledWeather(), search: NoSearch(), geocoder: NoSearch(), drives: NoSearch(),
                        scout: nil, sampleWeather: SampleWeatherService(now: { fixed }), defaults: defaults, now: { fixed })
    }

    @Test func withoutWeatherKitEveryWindowSaysWhyAndHasNoScore() async throws {
        let model = try model(sampleOn: false)
        let spot = try #require(CuratedSpots.spot(id: "mesa-arch"))
        let state = await model.forecasts.load(spot.coordinate)
        #expect(state == .unavailable(.weatherServiceNotEnabled))
        let light = model.dayLight(for: spot, on: LocalDay(year: 2026, month: 10, day: 7))
        #expect(!light.windows.isEmpty)
        for w in light.windows {
            #expect(w.score == nil)
            #expect(w.assessment == .noForecast(.weatherServiceNotEnabled))
        }
    }

    @Test func sampleModeScoresAndIsLabelledAsSample() async throws {
        let model = try model(sampleOn: true)
        let spot = try #require(CuratedSpots.spot(id: "mesa-arch"))
        _ = await model.forecasts.load(spot.coordinate)
        let light = model.dayLight(for: spot, on: LocalDay(year: 2026, month: 10, day: 7))
        let scored = light.windows.compactMap(\.assessment.lightScore)
        #expect(!scored.isEmpty)
        #expect(scored.allSatisfy { $0.source == .sample })
    }

    @Test func togglingSampleModeDropsOldForecasts() async throws {
        let model = try model(sampleOn: true)
        let c = Coordinate(latitude: 38.39, longitude: -109.87)
        _ = await model.forecasts.load(c)
        #expect(model.forecasts.state(for: c).forecast != nil)
        model.setSampleData(false)
        let state = await model.forecasts.load(c)
        #expect(state == .unavailable(.weatherServiceNotEnabled))
    }

    @Test func intentFollowsSpotUnlessChosen() throws {
        let model = try model(sampleOn: false)
        let mesa = try #require(CuratedSpots.spot(id: "mesa-arch"))
        #expect(model.intent(for: mesa) == .sunrise)
        model.preferredIntent = .night
        #expect(model.intent(for: mesa) == .night)
    }
}
