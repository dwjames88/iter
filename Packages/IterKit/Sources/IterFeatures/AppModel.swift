import Foundation
import Observation
import SwiftData
import IterCore
import IterAstro
import IterLight
import IterData
import IterServices

/// The service container and app-wide state. One per app; injected into the SwiftUI environment.
@MainActor
@Observable
public final class AppModel {
    public let store: IterStore
    public let forecasts: ForecastCenter
    public let engine: LightEngine
    public let scheduler: TripScheduler
    public let search: any PlaceSearching
    public let geocoder: any Geocoding
    public let drives: any DriveTimeProviding
    public let scout: (any Scouting)?

    /// Sample Data mode (Debug menu). Off by default; every screen showing sample data says so.
    public private(set) var sampleDataEnabled: Bool
    /// The intent chosen on Explore; nil means "each spot's best light".
    public var preferredIntent: LightIntent?
    /// Apple Weather attribution, loaded once (works even when the forecast itself is not enabled).
    public private(set) var attribution: WeatherAttributionInfo?
    /// The clock (injected for tests and snapshots).
    public var now: () -> Date

    @ObservationIgnored private let liveWeather: any WeatherProviding
    @ObservationIgnored private let defaults: UserDefaults
    public static let sampleDataKey = "IterSampleDataEnabled"

    public init(store: IterStore,
                weather: any WeatherProviding,
                search: any PlaceSearching,
                geocoder: any Geocoding,
                drives: any DriveTimeProviding,
                scout: (any Scouting)?,
                ephemeris: any Ephemeris = Astronomy(),
                defaults: UserDefaults = .standard,
                now: @escaping () -> Date = { Date() }) {
        self.store = store
        self.liveWeather = weather
        self.search = search
        self.geocoder = geocoder
        self.drives = drives
        self.scout = scout
        self.defaults = defaults
        self.now = now
        self.engine = LightEngine(ephemeris: ephemeris)
        self.scheduler = TripScheduler(engine: engine)
        let sample = defaults.bool(forKey: Self.sampleDataKey)
        self.sampleDataEnabled = sample
        self.forecasts = ForecastCenter(provider: sample ? CachedWeatherService(wrapping: SampleWeatherService()) : weather)
    }

    public var ephemeris: any Ephemeris { engine.ephemeris }

    /// The real app: WeatherKit (cached), MapKit, on-disk store.
    public static func live(store: IterStore, scout: (any Scouting)?) -> AppModel {
        AppModel(store: store,
                 weather: CachedWeatherService(wrapping: AppleWeatherService()),
                 search: MapKitPlaceSearch(),
                 geocoder: MapKitGeocoder(),
                 drives: MapKitDriveTimes(),
                 scout: scout)
    }

    public func setSampleData(_ enabled: Bool) {
        guard enabled != sampleDataEnabled else { return }
        sampleDataEnabled = enabled
        defaults.set(enabled, forKey: Self.sampleDataKey)
        forecasts.replaceProvider(enabled ? CachedWeatherService(wrapping: SampleWeatherService()) : liveWeather)
    }

    public func loadAttribution() async {
        attribution = await liveWeather.attribution()
    }

    /// Today in the given zone, from the injected clock.
    public func today(in zone: TimeZone) -> LocalDay { LocalDay(now(), in: zone) }

    /// Light for one spot and day, from whatever forecast state is current (requests one if needed).
    public func dayLight(for spot: Spot, on day: LocalDay) -> DayLight {
        forecasts.request(spot.coordinate)
        let state = forecasts.state(for: spot.coordinate)
        return engine.dayLight(for: spot, on: day, forecast: state.forecast, unavailable: state.unavailableReason, now: now())
    }

    public func outlook(for spot: Spot, from day: LocalDay, days: Int) -> [DayLight] {
        forecasts.request(spot.coordinate)
        let state = forecasts.state(for: spot.coordinate)
        return engine.outlook(for: spot, from: day, days: days, forecast: state.forecast, unavailable: state.unavailableReason, now: now())
    }

    /// The intent to show for a spot: the user's choice, else the spot's own best light.
    public func intent(for spot: Spot) -> LightIntent { preferredIntent ?? spot.defaultIntent }
}
