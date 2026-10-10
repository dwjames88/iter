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
    /// Keeps pinned trips ready offline (forecasts, drive legs, images).
    public let offline: PinnedTripDownloader
    public let scout: (any Scouting)?
    /// Finds places for Search Here and "<feature> in <area>" searches from several sources. Nil in tests and when
    /// the app has none; Explore then behaves as it did without it.
    public let discovery: (any Discovering)?
    /// The user's search choices: what they like to shoot, which sources, ordering, Google credentials.
    public let searchSettings: SearchSettingsModel
    /// The user's location for "Near you" (inert unless the app passes a live one).
    public let location: UserLocationModel

    /// Sample Data mode (Debug menu). Off by default; every screen showing sample data says so.
    public private(set) var sampleDataEnabled: Bool
    /// The intent chosen on Explore; nil means "each spot's best light".
    public var preferredIntent: LightIntent?
    /// Apple Weather attribution, loaded once (works even when the forecast itself is not enabled).
    public private(set) var attribution: WeatherAttributionInfo?
    /// The attribution of every selectable provider (and the current one), loaded by `loadAttribution()`.
    public private(set) var attributions: [ForecastSource: WeatherAttributionInfo] = [:]
    /// The user's weather choices, keys and per-provider status; owns the provider router.
    public let weather: WeatherSetup
    /// The first-run guide (see `OnboardingModel`).
    public let onboarding: OnboardingModel
    /// The clock (injected for tests and snapshots).
    public var now: () -> Date

    @ObservationIgnored private let liveWeather: any WeatherProviding
    @ObservationIgnored private let sampleWeather: any WeatherProviding
    @ObservationIgnored private let defaults: UserDefaults
    public static let sampleDataKey = "IterSampleDataEnabled"

    public init(store: IterStore,
                weather: any WeatherProviding,
                search: any PlaceSearching,
                geocoder: any Geocoding,
                drives: any DriveTimeProviding,
                scout: (any Scouting)?,
                discovery: (any Discovering)? = nil,
                searchSettings: SearchSettingsModel? = nil,
                weatherSetup: WeatherSetup? = nil,
                location: UserLocationModel = UserLocationModel(),
                onboarding: OnboardingModel? = nil,
                sampleWeather: any WeatherProviding = CachedWeatherService(wrapping: SampleWeatherService()),
                ephemeris: any Ephemeris = Astronomy(),
                defaults: UserDefaults = .standard,
                offlinePackDirectory: URL? = nil,
                now: @escaping () -> Date = { Date() }) {
        self.store = store
        self.liveWeather = weather
        self.sampleWeather = sampleWeather
        self.search = search
        self.geocoder = geocoder
        let offlineDrives = (drives as? OfflineDriveTimes) ?? OfflineDriveTimes(wrapping: drives)
        self.drives = offlineDrives
        self.scout = scout
        self.discovery = discovery
        self.searchSettings = searchSettings ?? SearchSettingsModel(defaults: defaults, keys: InMemoryDiscoveryKeyStore())
        self.location = location
        self.onboarding = onboarding ?? OnboardingModel(defaults: defaults)
        self.defaults = defaults
        self.now = now
        self.engine = LightEngine(ephemeris: ephemeris)
        self.scheduler = TripScheduler(engine: engine)
        let sample = defaults.bool(forKey: Self.sampleDataKey)
        self.sampleDataEnabled = sample
        self.forecasts = ForecastCenter(provider: sample ? sampleWeather : weather)
        // Without a setup (tests) the weather settings are hermetic: in-memory keys, no environment, `weather` is the Apple provider.
        self.offline = PinnedTripDownloader(store: store, forecasts: forecasts, scheduler: scheduler, drives: offlineDrives,
                                            packs: offlinePackDirectory.map { OfflinePackStore(root: $0) }, now: now)
        self.weather = weatherSetup ?? WeatherSetup(keyStore: InMemoryAPIKeyStore(), cacheDirectory: nil, defaults: defaults,
                                                    environment: { [:] }, launchArgument: { _ in nil }, apple: weather)
        self.weather.onChange = { [weak self] in
            guard let self else { return }
            self.forecasts.invalidateAll()
            Task { await self.loadAttribution() }
        }
    }

    public var ephemeris: any Ephemeris { engine.ephemeris }

    /// Which discovery engine the real app runs. `.stub` and `.off` are for screenshots (launch switch `-IterDiscoveryStub`).
    public enum DiscoveryChoice: Sendable {
        case live
        case off
        case stub(any Discovering)

        func resolve(keys: any DiscoveryKeyStore) -> (any Discovering)? {
            switch self {
            case .live: DiscoveryEngine.live(keys: keys)
            case .off: nil
            case .stub(let engine): engine
            }
        }
    }

    /// The real app: the weather router (Apple Weather, OpenWeather, Windy as the user chose), MapKit, on-disk store.
    /// `offlinePacks` is where pinned trips' offline packs live; pass a throwaway folder with an in-memory store, or
    /// the launch-time clean-up would remove the real packs (their trips are not in that store).
    public static func live(store: IterStore, scout: (any Scouting)?, discovery override: DiscoveryChoice = .live,
                            offlinePacks: URL? = OfflinePackStore.defaultRoot()) -> AppModel {
        let cache = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appending(path: "Iter/ForecastCache", directoryHint: .isDirectory)
        let setup = WeatherSetup(keyStore: KeychainAPIKeyStore(), cacheDirectory: cache)
        let keys = KeychainDiscoveryKeyStore()
        return AppModel(store: store,
                 weather: setup.router,
                 search: MapKitPlaceSearch(),
                 geocoder: MapKitGeocoder(),
                 drives: MapKitDriveTimes(),
                 scout: scout,
                 discovery: override.resolve(keys: keys),
                 searchSettings: SearchSettingsModel(keys: keys),
                 weatherSetup: setup,
                 location: .live(),
                 offlinePackDirectory: offlinePacks)
    }

    /// The discovery settings for a request starting now: the user's choices, with the library summary when they let
    /// it learn. Prompts, Search Here and feature searches all read this.
    public func discoverySettings() -> DiscoverySettings {
        searchSettings.discoverySettings(tasteSummary: searchSettings.learnsFromLibrary ? TasteSummary.make(store: store) : nil)
    }

    public func setSampleData(_ enabled: Bool) {
        guard enabled != sampleDataEnabled else { return }
        sampleDataEnabled = enabled
        defaults.set(enabled, forKey: Self.sampleDataKey)
        forecasts.replaceProvider(enabled ? sampleWeather : liveWeather)
    }

    public func loadAttribution() async {
        attribution = await liveWeather.attribution()
        var loaded: [ForecastSource: WeatherAttributionInfo] = [:]
        for source in Set(ForecastSource.selectable + [liveWeather.source]) where source != .sample {
            if let info = await weather.attribution(for: source) { loaded[source] = info }
        }
        if let current = attribution { loaded[liveWeather.source] = current }
        attributions = loaded
    }

    public func attribution(for source: ForecastSource) -> WeatherAttributionInfo? { attributions[source] }

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

    /// The next sunrise or sunset event at the spot (its own clock), scored from the current forecast state.
    public func nextLight(for spot: Spot) -> (day: LocalDay, window: LightWindow)? {
        forecasts.request(spot.coordinate)
        let state = forecasts.state(for: spot.coordinate)
        return engine.nextEvent(for: spot, forecast: state.forecast, unavailable: state.unavailableReason, now: now())
    }

    /// Today's windows still ahead plus all of tomorrow's.
    public func upcomingWindows(for spot: Spot) -> [(day: LocalDay, window: LightWindow)] {
        forecasts.request(spot.coordinate)
        let state = forecasts.state(for: spot.coordinate)
        return engine.upcomingWindows(for: spot, forecast: state.forecast, unavailable: state.unavailableReason, now: now())
    }

    /// Why weather is missing for the whole app, or `.ok`.
    public var weatherStatus: WeatherStatus { forecasts.status }

    /// A spot was saved or created: fetch its forecast now so it shows a score straight away.
    public func spotSaved(_ spot: Spot) {
        forecasts.request(spot.coordinate)
    }

    /// The intent to show for a spot: the user's choice, else the spot's own best light.
    public func intent(for spot: Spot) -> LightIntent { preferredIntent ?? spot.defaultIntent }
}
