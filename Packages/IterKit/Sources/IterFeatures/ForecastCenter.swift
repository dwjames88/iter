import Foundation
import Observation
import IterCore

/// The state of the forecast for one place. Shared by every screen so a forecast is fetched once.
public enum ForecastState: Sendable, Equatable {
    case loading
    case loaded(Forecast)
    case unavailable(ForecastUnavailableReason)

    public var forecast: Forecast? {
        if case .loaded(let f) = self { return f }
        return nil
    }

    /// The reason to pass to the light engine when there is no forecast.
    public var unavailableReason: ForecastUnavailableReason? {
        switch self {
        case .loading: .notLoaded
        case .loaded: nil
        case .unavailable(let r): r
        }
    }
}

/// Why weather is missing for the whole app, shown once per screen. Individual rows never carry a "no forecast" state.
public enum WeatherStatus: Equatable, Sendable {
    case ok
    /// The chosen provider needs an API key and none is set.
    case needsKey(ForecastSource)
    /// The provider could not be reached. `lastUpdate` is the newest forecast still on screen, if any.
    case offline(ForecastSource, lastUpdate: Date?)
    /// Key rejected, daily cap, testing key, provider failed, WeatherKit not enabled, service failed.
    case failed(ForecastUnavailableReason, lastUpdate: Date?)
}

/// Fetches and holds forecasts per place (keyed by `Coordinate.cacheKey`). Main-actor state, async fetches.
@MainActor
@Observable
public final class ForecastCenter {
    public private(set) var states: [String: ForecastState] = [:]
    /// Bumped whenever any state changes or the provider is swapped, so views can recompute light.
    public private(set) var revision = 0

    /// Why weather is missing, or `.ok`. Updated after every completed fetch.
    public private(set) var status: WeatherStatus = .ok
    /// The most recent successful forecast per key. A failed fetch leaves it on screen.
    public private(set) var lastGood: [String: Forecast] = [:]

    @ObservationIgnored private var failedKeys: Set<String> = []
    @ObservationIgnored private var provider: any WeatherProviding
    @ObservationIgnored private var inFlight: [String: Task<Void, Never>] = [:]

    public init(provider: any WeatherProviding) {
        self.provider = provider
    }

    public var source: ForecastSource { provider.source }

    /// Swap the provider (Sample Data mode) and drop everything fetched with the old one.
    public func replaceProvider(_ provider: any WeatherProviding) {
        self.provider = provider
        inFlight.values.forEach { $0.cancel() }
        inFlight = [:]
        states = [:]
        lastGood = [:]
        failedKeys = []
        status = .ok
        revision += 1
    }

    /// Drops every state and in-flight fetch but keeps the provider (its settings or keys changed), so screens refetch.
    public func invalidateAll() {
        inFlight.values.forEach { $0.cancel() }
        inFlight = [:]
        states = [:]
        failedKeys = []
        status = .ok
        revision += 1
    }

    public func state(for coordinate: Coordinate) -> ForecastState {
        states[coordinate.cacheKey] ?? .loading
    }

    public func isLoading(_ coordinate: Coordinate) -> Bool {
        if case .loading = state(for: coordinate) { return true }
        return false
    }

    /// Starts a fetch if there is no state yet (or `force`). Returns immediately.
    public func request(_ coordinate: Coordinate, force: Bool = false) {
        let key = coordinate.cacheKey
        if !force, states[key] != nil || inFlight[key] != nil { return }
        IterPerf.once("forecast.firstRequest")
        if states[key] == nil { states[key] = lastGood[key].map { .loaded($0) } ?? .loading }
        let provider = self.provider
        inFlight[key] = Task { [weak self] in
            let result: FetchResult
            do {
                result = .success(try await provider.forecast(for: coordinate))
            } catch let error as WeatherError {
                result = .failure(error.unavailableReason)
            } catch is CancellationError {
                return
            } catch {
                result = .failure(.serviceFailed(detail: String(describing: error)))
            }
            guard !Task.isCancelled, let self else { return }
            self.finish(key: key, result)
        }
    }

    private enum FetchResult {
        case success(Forecast)
        case failure(ForecastUnavailableReason)
    }

    private func finish(key: String, _ result: FetchResult) {
        switch result {
        case .success(let forecast):
            lastGood[key] = forecast
            failedKeys.remove(key)
            states[key] = .loaded(forecast)
            status = .ok
        case .failure(let reason):
            states[key] = lastGood[key].map { .loaded($0) } ?? .unavailable(reason)
            switch reason {
            case .inThePast, .beyondHorizon, .notLoaded:
                break
            default:
                failedKeys.insert(key)
                let last = lastGood.values.map(\.fetchedAt).max()
                switch reason {
                case .missingAPIKey(let source): status = .needsKey(source)
                case .offline(let source): status = .offline(source, lastUpdate: last)
                default: status = .failed(reason, lastUpdate: last)
                }
            }
        }
        inFlight[key] = nil
        revision += 1
        IterPerf.count("forecast.finish")
        if inFlight.isEmpty { IterPerf.mark("forecast.idle", "states=\(states.count)") }
    }

    public func requestAll(_ coordinates: [Coordinate]) {
        for c in coordinates { request(c) }
    }

    /// Fetch and wait (for tests and the smoke hook).
    public func load(_ coordinate: Coordinate) async -> ForecastState {
        request(coordinate)
        await inFlight[coordinate.cacheKey]?.value
        return state(for: coordinate)
    }

    /// Retry everything that failed.
    public func retryFailed() {
        var keys = failedKeys
        for (key, state) in states { if case .unavailable = state { keys.insert(key) } }
        for key in keys.sorted() {
            if let c = Self.coordinate(fromKey: key) { request(c, force: true) }
        }
    }

    public func attribution() async -> WeatherAttributionInfo? {
        await provider.attribution()
    }

    static func coordinate(fromKey key: String) -> Coordinate? {
        let parts = key.split(separator: ",").compactMap { Double($0) }
        guard parts.count == 2 else { return nil }
        return Coordinate(latitude: parts[0], longitude: parts[1])
    }
}
