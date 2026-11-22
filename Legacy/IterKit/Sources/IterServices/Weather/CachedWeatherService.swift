import Foundation
import IterCore

/// Wraps any `WeatherProviding` with a per-location cache, request coalescing and a memo of "not enabled".
public actor CachedWeatherService: WeatherProviding {
    public static let defaultTimeToLive: TimeInterval = 30 * 60
    public static let defaultNotEnabledMemo: TimeInterval = 10 * 60

    private let base: any WeatherProviding
    private let timeToLive: TimeInterval
    private let notEnabledMemo: TimeInterval
    private let now: @Sendable () -> Date

    private var entries: [String: (forecast: Forecast, storedAt: Date)] = [:]
    private var inflight: [String: Task<Forecast, any Error>] = [:]
    private var notEnabledUntil: Date?

    public nonisolated var source: ForecastSource { base.source }

    public init(wrapping base: any WeatherProviding,
                timeToLive: TimeInterval = CachedWeatherService.defaultTimeToLive,
                notEnabledMemo: TimeInterval = CachedWeatherService.defaultNotEnabledMemo,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.base = base
        self.timeToLive = timeToLive
        self.notEnabledMemo = notEnabledMemo
        self.now = now
    }

    public func forecast(for coordinate: Coordinate) async throws -> Forecast {
        let key = coordinate.cacheKey
        let current = now()

        if let until = notEnabledUntil {
            if current < until { throw WeatherError.notEnabled }
            notEnabledUntil = nil
        }
        if let hit = entries[key] {
            if current.timeIntervalSince(hit.storedAt) < timeToLive { return hit.forecast }
            entries[key] = nil
        }
        if let running = inflight[key] {
            return try await running.value
        }

        let provider = base
        // Unstructured on purpose: the fetch is shared by every waiter, so one caller cancelling must not cancel it for the rest.
        let task = Task { try await provider.forecast(for: coordinate) }
        inflight[key] = task
        do {
            let forecast = try await task.value
            entries[key] = (forecast, now())
            inflight[key] = nil
            return forecast
        } catch {
            inflight[key] = nil
            if let e = error as? WeatherError, e == .notEnabled {
                notEnabledUntil = now().addingTimeInterval(notEnabledMemo)
            }
            throw error
        }
    }

    public nonisolated func attribution() async -> WeatherAttributionInfo? {
        await base.attribution()
    }

    /// Drops every cached forecast and the "not enabled" memo (pull to refresh, entitlement just enabled).
    public func invalidate() {
        entries.removeAll()
        notEnabledUntil = nil
    }
}
