import Foundation
import Synchronization
import Testing
import IterCore
@testable import IterFeatures

/// A provider the test can switch between answering and failing.
private final class FlakyWeather: WeatherProviding {
    private let failure = Mutex<WeatherError?>(nil)
    let fetched: Date
    var source: ForecastSource { .openWeather }
    init(fetched: Date = Date(timeIntervalSince1970: 1_790_000_000)) { self.fetched = fetched }
    func fail(with error: WeatherError?) { failure.withLock { $0 = error } }
    func forecast(for coordinate: Coordinate) async throws -> Forecast {
        if let error = failure.withLock({ $0 }) { throw error }
        return Forecast(coordinate: coordinate, hours: [], days: [], fetchedAt: fetched, source: .openWeather)
    }
    func attribution() async -> WeatherAttributionInfo? { nil }
}

private let a = Coordinate(latitude: 38.57, longitude: -109.55)
private let b = Coordinate(latitude: 44.0, longitude: -110.0)

@MainActor
@Suite struct ForecastStatusTests {
    @Test func successIsOk() async {
        let center = ForecastCenter(provider: FlakyWeather())
        _ = await center.load(a)
        #expect(center.status == .ok)
        #expect(center.lastGood[a.cacheKey] != nil)
    }

    @Test func missingKeyOfflineAndOtherFailuresMapToStatuses() async {
        let provider = FlakyWeather()
        let center = ForecastCenter(provider: provider)
        provider.fail(with: .missingKey(.openWeather))
        _ = await center.load(a)
        #expect(center.status == .needsKey(.openWeather))
        #expect(center.state(for: a) == .unavailable(.missingAPIKey(.openWeather)))
        provider.fail(with: .offline(.openWeather))
        _ = await center.load(b)
        #expect(center.status == .offline(.openWeather, lastUpdate: nil))
        provider.fail(with: .overDailyLimit(.openWeather))
        _ = await center.load(Coordinate(latitude: 1, longitude: 1))
        #expect(center.status == .failed(.dailyLimitReached(.openWeather), lastUpdate: nil))
    }

    @Test func aLoadedForecastStaysAfterAFailureAndReportsItsAge() async {
        let provider = FlakyWeather()
        let center = ForecastCenter(provider: provider)
        let first = await center.load(a)
        #expect(first.forecast != nil)
        provider.fail(with: .offline(.openWeather))
        center.request(a, force: true)
        _ = await center.load(a)
        #expect(center.state(for: a).forecast?.fetchedAt == provider.fetched)
        #expect(center.status == .offline(.openWeather, lastUpdate: provider.fetched))
        // Invalidating keeps the stale forecast as the starting state while the refetch runs.
        center.invalidateAll()
        #expect(center.status == .ok)
        center.request(a)
        #expect(center.state(for: a).forecast != nil)
        #expect(!center.isLoading(a))
    }

    @Test func retryFailedAlsoRetriesKeysShowingStaleData() async {
        let provider = FlakyWeather()
        let center = ForecastCenter(provider: provider)
        _ = await center.load(a)
        provider.fail(with: .offline(.openWeather))
        center.request(a, force: true)
        _ = await center.load(a)
        #expect(center.status != .ok)
        provider.fail(with: nil)
        center.retryFailed()
        _ = await center.load(a)
        #expect(center.status == .ok)
    }

    @Test func replacingTheProviderClearsStaleData() async {
        let center = ForecastCenter(provider: FlakyWeather())
        _ = await center.load(a)
        center.replaceProvider(FlakyWeather())
        #expect(center.lastGood.isEmpty)
        #expect(center.state(for: a) == .loading)
        #expect(center.isLoading(a))
        #expect(center.status == .ok)
    }
}
