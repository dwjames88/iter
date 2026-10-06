import Foundation
import Observation
import IterCore
import IterServices

/// What Settings ▸ Weather shows for one provider.
public enum WeatherProviderStatus: Hashable, Sendable {
    case working(lastUpdate: Date)
    case needsKey
    /// Apple Weather without the WeatherKit entitlement.
    case notEnabled
    /// A Windy testing key: its data is shuffled, so Iter never scores from it.
    case testingKey
    case keyRejected
    case dailyCap(calls: Int, cap: Int)
    case failed(detail: String)
    case notChecked
    case checking
}

/// The user's weather choices and what is known about each provider. Owns the provider factory and the fallback router.
/// Choices (primary, fallback, Windy key type and model, call caps) persist in UserDefaults; API keys never do, they go
/// to the key store (the Keychain in the app).
@MainActor
@Observable
public final class WeatherSetup {
    public static let probeCoordinate = Coordinate(latitude: 38.3659, longitude: -109.6213)
    /// The providers the user can pick, in display order.
    public static let providers: [ForecastSource] = ForecastSource.selectable

    public let factory: WeatherProviderFactory
    public let router: WeatherRouter
    public private(set) var settings: WeatherSettings
    public private(set) var lastSuccess: [ForecastSource: Date] = [:]
    public private(set) var lastError: [ForecastSource: WeatherError] = [:]
    public private(set) var checking: Set<ForecastSource> = []
    /// Called after the settings or a key changed and the router was re-pointed (the app drops its forecasts here).
    @ObservationIgnored public var onChange: (@MainActor () -> Void)?

    /// Bumped on every observer report, key change and call, so views re-read key presence and call counts.
    private var revision = 0
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var applying: Task<Void, Never>?

    /// Lets the router's observer reach this object without a retain cycle. Main-actor isolated, so it is Sendable.
    @MainActor private final class Relay {
        weak var target: WeatherSetup?
    }

    public init(keyStore: any APIKeyStore, cacheDirectory: URL?, defaults: UserDefaults = .standard,
                transport: any HTTPTransport = URLSessionTransport(),
                environment: @escaping @Sendable () -> [String: String] = { ProcessInfo.processInfo.environment },
                launchArgument: @escaping @Sendable (String) -> String? = APIKeyResolver.processLaunchArgument,
                apple: (any WeatherProviding)? = nil,
                now: @escaping @Sendable () -> Date = { Date() }) {
        let settings = Self.loadSettings(defaults)
        let factory = WeatherProviderFactory(keyStore: keyStore, cacheDirectory: cacheDirectory, defaults: defaults,
                                             transport: transport, environment: environment, launchArgument: launchArgument,
                                             apple: apple, now: now)
        let relay = Relay()
        self.defaults = defaults
        self.settings = settings
        self.factory = factory
        self.router = factory.makeRouter(settings: settings) { source, result in
            Task { @MainActor in relay.target?.record(source, result) }
        }
        relay.target = self
    }

    // MARK: Persistence

    private enum Key {
        static let primary = "iter.weather.primary"
        static let fallback = "iter.weather.fallback"
        static let windyKeyType = "iter.weather.windyKeyType"
        static let windyModelMode = "iter.weather.windyModelMode"
        static let openWeatherCap = "iter.weather.cap.openweather"
        static let windyCap = "iter.weather.cap.windy"
    }

    static func loadSettings(_ d: UserDefaults) -> WeatherSettings {
        var s = WeatherSettings()
        if let p = d.string(forKey: Key.primary).flatMap(ForecastSource.init(rawValue:)), ForecastSource.selectable.contains(p) { s.primary = p }
        if let f = d.string(forKey: Key.fallback).flatMap(ForecastSource.init(rawValue:)), ForecastSource.selectable.contains(f), f != s.primary { s.fallback = f }
        if let t = d.string(forKey: Key.windyKeyType).flatMap(WindyKeyType.init(rawValue:)) { s.windyKeyType = t }
        if let m = d.string(forKey: Key.windyModelMode).flatMap(WindyModelMode.init(rawValue:)) { s.windyModelMode = m }
        if d.object(forKey: Key.openWeatherCap) != nil { s.openWeatherDailyCap = max(0, d.integer(forKey: Key.openWeatherCap)) }
        if d.object(forKey: Key.windyCap) != nil { s.windyDailyCap = max(0, d.integer(forKey: Key.windyCap)) }
        return s
    }

    private func persist() {
        defaults.set(settings.primary.rawValue, forKey: Key.primary)
        if let f = settings.fallback { defaults.set(f.rawValue, forKey: Key.fallback) } else { defaults.removeObject(forKey: Key.fallback) }
        defaults.set(settings.windyKeyType.rawValue, forKey: Key.windyKeyType)
        defaults.set(settings.windyModelMode.rawValue, forKey: Key.windyModelMode)
        defaults.set(settings.openWeatherDailyCap, forKey: Key.openWeatherCap)
        defaults.set(settings.windyDailyCap, forKey: Key.windyCap)
    }

    // MARK: Choices

    public func selectPrimary(_ source: ForecastSource) {
        guard Self.providers.contains(source) else { return }
        change { s in
            s.primary = source
            if s.fallback == source { s.fallback = nil }
        }
    }

    public func selectFallback(_ source: ForecastSource?) {
        if let source, !Self.providers.contains(source) { return }
        change { $0.fallback = (source == $0.primary) ? nil : source }
    }

    public func setWindyKeyType(_ type: WindyKeyType) { change { $0.windyKeyType = type } }
    public func setWindyModelMode(_ mode: WindyModelMode) { change { $0.windyModelMode = mode } }

    /// Changes the daily call cap of OpenWeather or Windy. Ignored for other sources.
    public func setCap(_ cap: Int, for source: ForecastSource) {
        let cap = max(0, cap)
        switch source {
        case .openWeather: change { $0.openWeatherDailyCap = cap }
        case .windy: change { $0.windyDailyCap = cap }
        case .appleWeather, .sample: break
        }
    }

    public func cap(for source: ForecastSource) -> Int? {
        switch source {
        case .openWeather: settings.openWeatherDailyCap
        case .windy: settings.windyDailyCap
        case .appleWeather, .sample: nil
        }
    }

    private func change(_ edit: (inout WeatherSettings) -> Void) {
        var new = settings
        edit(&new)
        guard new != settings else { return }
        settings = new
        persist()
        reapply()
    }

    /// Points the router at the current settings, then tells the app to drop its forecasts. Await `settled()` in tests.
    private func reapply(probing source: ForecastSource? = nil) {
        let previous = applying
        let settings = self.settings
        applying = Task { [factory, router] in
            await previous?.value
            await factory.apply(settings, to: router)
            self.revision += 1
            self.onChange?()
            if let source { await self.check(source) }
        }
    }

    /// Waits for the last settings change to reach the router.
    public func settled() async { await applying?.value }

    // MARK: Keys

    /// Whether the provider takes a key and where the key in use comes from (nil = none). Never exposes the key.
    public func keyOrigin(for source: ForecastSource) -> APIKeyOrigin? {
        _ = revision
        return factory.keys.resolve(source)?.origin
    }

    public func hasKey(for source: ForecastSource) -> Bool { keyOrigin(for: source) != nil }

    /// Saves a key to the key store (trimmed; empty is ignored), then refetches and probes the provider.
    public func setKey(_ key: String, for source: ForecastSource) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard source.needsAPIKey, !trimmed.isEmpty else { return }
        try factory.keys.store.setKey(trimmed, for: source)
        keyChanged(source)
    }

    public func removeKey(for source: ForecastSource) throws {
        guard source.needsAPIKey else { return }
        try factory.keys.store.removeKey(for: source)
        keyChanged(source)
    }

    private func keyChanged(_ source: ForecastSource) {
        lastError[source] = nil
        lastSuccess[source] = nil
        revision += 1
        reapply(probing: hasKey(for: source) ? source : nil)
    }

    // MARK: Status

    /// Reports one attempt (the router's observer calls this; tests and fixtures may too).
    public func record(_ source: ForecastSource, _ result: Result<Date, WeatherError>) {
        switch result {
        case .success(let date):
            lastSuccess[source] = date
            lastError[source] = nil
        case .failure(let error):
            lastError[source] = error
        }
        revision += 1
    }

    /// Calls made today and the daily cap (nil for providers without a budget).
    public func usage(for source: ForecastSource) -> (calls: Int, cap: Int)? {
        _ = revision
        guard let cap = cap(for: source) else { return nil }
        return (factory.usage(for: source).calls, cap)
    }

    public func status(for source: ForecastSource) -> WeatherProviderStatus {
        _ = revision
        if checking.contains(source) { return .checking }
        if source.needsAPIKey, !hasKey(for: source) { return .needsKey }
        if let error = lastError[source] {
            switch error {
            case .notEnabled: return .notEnabled
            case .missingKey: return .needsKey
            case .keyRejected: return .keyRejected
            case .testingKey: return .testingKey
            case .overDailyLimit:
                let u = usage(for: source)
                return .dailyCap(calls: u?.calls ?? 0, cap: u?.cap ?? 0)
            case .failed(let detail), .provider(_, let detail): return .failed(detail: detail)
            }
        }
        if source == .windy, settings.windyKeyType == .testing { return .testingKey }
        if let date = lastSuccess[source] { return .working(lastUpdate: date) }
        return .notChecked
    }

    /// Asks one provider directly for a forecast at a fixed place, without touching the selection or the app's forecasts.
    public func check(_ source: ForecastSource) async {
        guard !checking.contains(source) else { return }
        checking.insert(source)
        defer { checking.remove(source) }
        let provider = factory.provider(for: source, settings: settings)
        do {
            let forecast = try await provider.forecast(for: Self.probeCoordinate)
            record(source, .success(forecast.fetchedAt))
        } catch is CancellationError {
        } catch let error as WeatherError {
            record(source, .failure(error))
        } catch {
            record(source, .failure(.provider(source, String(describing: type(of: error)))))
        }
    }

    /// The attribution a provider requires, built straight from the provider (works whether or not it is in use).
    public func attribution(for source: ForecastSource) async -> WeatherAttributionInfo? {
        await factory.provider(for: source, settings: settings).attribution()
    }
}
