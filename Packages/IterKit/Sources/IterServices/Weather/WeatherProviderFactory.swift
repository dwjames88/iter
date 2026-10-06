import Foundation
import IterCore

/// What the user chose in Settings ▸ Weather.
public struct WeatherSettings: Hashable, Sendable {
    public var primary: ForecastSource
    public var fallback: ForecastSource?
    public var windyKeyType: WindyKeyType
    public var windyModelMode: WindyModelMode
    public var openWeatherDailyCap: Int
    public var windyDailyCap: Int

    public init(primary: ForecastSource = .appleWeather, fallback: ForecastSource? = nil,
                windyKeyType: WindyKeyType = .testing, windyModelMode: WindyModelMode = .bestForSpot,
                openWeatherDailyCap: Int = 800, windyDailyCap: Int = 400) {
        self.primary = primary
        self.fallback = fallback
        self.windyKeyType = windyKeyType
        self.windyModelMode = windyModelMode
        self.openWeatherDailyCap = openWeatherDailyCap
        self.windyDailyCap = windyDailyCap
    }

    /// Primary then fallback, without a repeat.
    public var order: [ForecastSource] {
        var out = [primary]
        if let fallback, fallback != primary { out.append(fallback) }
        return out
    }
}

/// Builds the live provider stack so the app only passes settings. Owns the shared call budget, key resolver and caches.
///
///     let factory = WeatherProviderFactory(keyStore: KeychainAPIKeyStore(), cacheDirectory: appSupport.appending(path: "Iter/ForecastCache"))
///     let router = factory.makeRouter(settings: settings, observer: { source, result in ... })
///     // Settings changed:
///     await factory.apply(settings, to: router)
public final class WeatherProviderFactory: Sendable {
    public let keys: APIKeyResolver
    public let budget: CallBudget
    private let transport: any HTTPTransport
    private let openWeatherCache: ProviderCache
    private let windyCache: ProviderCache
    private let apple: any WeatherProviding
    private let now: @Sendable () -> Date

    /// - Parameters:
    ///   - cacheDirectory: where OpenWeather forecasts persist (`Application Support/Iter/ForecastCache`); the factory adds `openweather/`. nil = memory only.
    ///   - defaults: holds the per-day call counts (counts only, no keys).
    ///   - apple: the Apple provider; defaults to `CachedWeatherService(wrapping: AppleWeatherService())`.
    public init(keyStore: any APIKeyStore, cacheDirectory: URL?, defaults: UserDefaults = .standard,
                transport: any HTTPTransport = URLSessionTransport(),
                environment: @escaping @Sendable () -> [String: String] = { ProcessInfo.processInfo.environment },
                launchArgument: @escaping @Sendable (String) -> String? = APIKeyResolver.processLaunchArgument,
                apple: (any WeatherProviding)? = nil,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.keys = APIKeyResolver(store: keyStore, environment: environment, launchArgument: launchArgument)
        self.budget = CallBudget(defaults: defaults, now: now)
        self.transport = transport
        self.now = now
        self.openWeatherCache = ProviderCache(directory: cacheDirectory?.appendingPathComponent("openweather", isDirectory: true),
                                              validity: .throughNextClockHour, now: now)
        self.windyCache = ProviderCache(directory: nil, validity: .interval(3 * 3600), now: now)
        self.apple = apple ?? CachedWeatherService(wrapping: AppleWeatherService(), now: now)
    }

    public func provider(for source: ForecastSource, settings: WeatherSettings) -> any WeatherProviding {
        budget.setCap(settings.openWeatherDailyCap, for: .openWeather)
        budget.setCap(settings.windyDailyCap, for: .windy)
        switch source {
        case .appleWeather: return apple
        case .openWeather: return OpenWeatherService(keys: keys, transport: transport, cache: openWeatherCache, budget: budget, now: now)
        case .windy:
            return WindyService(keys: keys, transport: transport, cache: windyCache, budget: budget,
                                keyType: settings.windyKeyType, modelMode: settings.windyModelMode, now: now)
        case .sample: return SampleWeatherService(now: now)
        }
    }

    public func providers(for settings: WeatherSettings) -> [any WeatherProviding] {
        settings.order.map { provider(for: $0, settings: settings) }
    }

    public func makeRouter(settings: WeatherSettings, observer: WeatherRouter.Observer? = nil) -> WeatherRouter {
        WeatherRouter(providers: providers(for: settings), observer: observer)
    }

    /// Re-points a running router at new settings.
    public func apply(_ settings: WeatherSettings, to router: WeatherRouter) async {
        await router.setProviders(providers(for: settings))
    }

    /// Calls made today and the cap, for "Calls today 12 / 800".
    public func usage(for source: ForecastSource) -> (calls: Int, cap: Int?) {
        (budget.callsToday(for: source), budget.cap(for: source))
    }
}
