import Foundation
import SwiftUI
import IterCore
import IterData
import IterServices
import IterFeatures
import IterDesign
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
        // Sample weather is only ever shown in Sample Data mode, so the fixture switches the mode on like the app does.
        defaults.set(weather == .sample, forKey: AppModel.sampleDataKey)
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

    /// A model for the Settings ▸ Weather snapshots: the chosen providers, the keys "saved" in the in-memory store (never probed,
    /// so no network) and the providers that last answered at the fixed clock.
    static func weatherSettingsModel(weather: Weather = .notEnabled, primary: ForecastSource, fallback: ForecastSource? = nil,
                                     keys: [ForecastSource] = [], working: [ForecastSource] = []) async -> AppModel {
        let model = Self.model(weather: weather, seedTrip: false, saved: [])
        let setup = model.weather
        for source in keys { try? setup.factory.keys.store.setKey("fixture-key", for: source) }
        setup.selectPrimary(primary)
        setup.selectFallback(fallback)
        await setup.settled()
        for source in working { setup.record(source, .success(now)) }
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

extension Fixtures {
    /// `view` as the detail column of the real window: a flat stand-in for the sidebar (its ideal width, 240) on the
    /// left and the view in the remaining width. Screens that split their own width (Explore and Scout results use
    /// a list of 300...520 beside a map) lay out differently in a full-width bare window than beside the sidebar,
    /// most of all in the compact window (list 479 wide bare, 360 in the real shell).
    static func inDetailColumn<V: View>(_ view: V) -> some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                IterColor.backgroundSystemWindow
                    .frame(width: IterSize.sidebarIdeal)
                    .overlay(alignment: .trailing) { Divider() }
                view.frame(width: max(0, geo.size.width - IterSize.sidebarIdeal))
            }
        }
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
