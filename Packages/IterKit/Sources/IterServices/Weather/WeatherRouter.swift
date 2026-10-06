import Foundation
import Synchronization
import IterCore

/// Tries the user's providers in order. The first to answer wins and its forecast records which earlier ones failed in
/// `fallbackFrom`. If all fail, the FIRST provider's error is thrown (the one the user chose). Every attempt is reported
/// to the observer (source and the forecast's fetch time, or the error) so Settings can show per-provider status.
public actor WeatherRouter: WeatherProviding {
    public typealias Observer = @Sendable (ForecastSource, Result<Date, WeatherError>) -> Void

    private var providers: [any WeatherProviding]
    private var observer: Observer?
    private let primarySource: Mutex<ForecastSource>

    /// The first provider's source (`.appleWeather` while the list is empty).
    public nonisolated var source: ForecastSource { primarySource.withLock { $0 } }

    public init(providers: [any WeatherProviding], observer: Observer? = nil) {
        self.providers = providers
        self.observer = observer
        self.primarySource = Mutex(providers.first?.source ?? .appleWeather)
    }

    /// Replaces the ordered list at run time (Settings changed).
    public func setProviders(_ providers: [any WeatherProviding]) {
        self.providers = providers
        primarySource.withLock { $0 = providers.first?.source ?? .appleWeather }
    }

    public func setObserver(_ observer: Observer?) {
        self.observer = observer
    }

    public func forecast(for coordinate: Coordinate) async throws -> Forecast {
        let list = providers
        var failed: [ForecastSource] = []
        var firstError: WeatherError?
        for provider in list {
            do {
                var forecast = try await provider.forecast(for: coordinate)
                forecast.fallbackFrom = failed
                observer?(provider.source, .success(forecast.fetchedAt))
                return forecast
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                let e = (error as? WeatherError) ?? .provider(provider.source, "\(type(of: error))")
                observer?(provider.source, .failure(e))
                failed.append(provider.source)
                if firstError == nil { firstError = e }
            }
        }
        throw firstError ?? WeatherError.failed("No weather provider is configured")
    }

    /// The first provider's attribution.
    public nonisolated func attribution() async -> WeatherAttributionInfo? {
        await attribution(for: source)
    }

    /// The attribution of a specific provider (the one that supplied a forecast).
    public func attribution(for source: ForecastSource) async -> WeatherAttributionInfo? {
        guard let p = providers.first(where: { $0.source == source }) else { return nil }
        return await p.attribution()
    }
}
