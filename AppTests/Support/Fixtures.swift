import Foundation
import SwiftUI
import IterCore
import IterData
import IterServices
import IterFeatures
@testable import Iter

/// Deterministic app states for snapshots and app tests: in-memory store, fixed clock, sample or absent weather,
/// and MapKit stand-ins (no network).
@MainActor
enum Fixtures {
    /// Tue 6 Oct 2026, 10:00 in Denver.
    nonisolated static let now = LocalDay(year: 2026, month: 10, day: 6).at(hour: 10, in: TimeZone(identifier: "America/Denver")!)

    enum Weather { case sample, notEnabled, failed }

    static func model(weather: Weather = .sample, seedTrip: Bool = true, saved: [String] = ["mesa-arch", "tunnel-view"]) -> AppModel {
        let container = try! IterSchema.makeContainer(inMemory: true)
        let store = IterStore(container: container)
        store.actionName = StoreActionText.name
        let defaults = UserDefaults(suiteName: "IterFixtures-\(UUID().uuidString)")!
        let clock: @Sendable () -> Date = { now }
        let sample = CachedWeatherService(wrapping: SampleWeatherService(now: clock))
        let live: any WeatherProviding
        switch weather {
        case .sample: live = sample
        case .notEnabled: live = FailingWeather(error: .notEnabled)
        case .failed: live = FailingWeather(error: .failed("offline"))
        }
        let model = AppModel(store: store, weather: live, search: StubSearch(), geocoder: StubGeocoder(),
                             drives: EstimateDrives(), scout: nil, sampleWeather: sample, defaults: defaults, now: { now })
        if seedTrip { _ = store.seedSampleTrip(startDay: LocalDay(year: 2026, month: 10, day: 7)) }
        for id in saved { if let s = CuratedSpots.spot(id: id) { store.setSaved(s, true) } }
        return model
    }

    /// A view wired the way the app wires it.
    static func host<V: View>(_ view: V, model: AppModel, navigation: AppNavigation = AppNavigation()) -> some View {
        view
            .environment(model)
            .environment(navigation)
            .modelContainer(model.store.container)
    }
}

struct FailingWeather: WeatherProviding {
    let error: WeatherError
    var source: ForecastSource { .appleWeather }
    func forecast(for coordinate: Coordinate) async throws -> Forecast { throw error }
    func attribution() async -> WeatherAttributionInfo? { nil }
}

struct StubSearch: PlaceSearching {
    func search(_ query: String, near region: GeoRegion?) async throws -> [PlaceResult] { [] }
    func pointsOfInterest(near center: Coordinate, radiusMeters: Double, categories: [String]) async throws -> [PlaceResult] { [] }
}

struct StubGeocoder: Geocoding {
    func reverseGeocode(_ coordinate: Coordinate) async throws -> PlaceResult {
        PlaceResult(id: "stub", name: "Dropped pin", locality: "Moab, UT", coordinate: coordinate,
                    timeZoneIdentifier: "America/Denver", pointOfInterestCategory: nil)
    }
    func geocode(_ query: String) async throws -> [PlaceResult] { [] }
}

/// Labelled straight-line estimates: deterministic and offline.
struct EstimateDrives: DriveTimeProviding {
    func drive(from a: Coordinate, to b: Coordinate) async throws -> DriveLeg { DriveLeg.estimate(from: a, to: b) }
}
