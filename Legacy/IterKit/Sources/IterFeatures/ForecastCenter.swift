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
    /// Bumped whenever what is on screen changes or the provider is swapped, so views can recompute light. A batch of
    /// fetches that finish close together bumps it once, and a result identical to what is shown does not bump it.
    public private(set) var revision = 0

    /// Why weather is missing, or `.ok`. Updated after every completed fetch.
    public private(set) var status: WeatherStatus = .ok
    /// The most recent successful forecast per key. A failed fetch leaves it on screen.
    public private(set) var lastGood: [String: Forecast] = [:]

    @ObservationIgnored private var failedKeys: Set<String> = []
    /// Keys whose state came from an offline pack; the first ordinary `request` still refetches them.
    @ObservationIgnored private var seededKeys: Set<String> = []
    @ObservationIgnored private var provider: any WeatherProviding
    @ObservationIgnored private var inFlight: [String: Task<Void, Never>] = [:]
    /// Finished fetches not yet applied. Applied together when the last fetch of a batch lands, or after `coalescing`.
    @ObservationIgnored private var pending: [(key: String, result: FetchResult)] = []
    @ObservationIgnored private var flushTask: Task<Void, Never>?
    @ObservationIgnored private let coalescing: Duration

    /// - Parameter coalescing: how long results of a batch that is still running wait to be shown together. The last
    ///   fetch to finish shows everything at once, so a lone request is never delayed.
    public init(provider: any WeatherProviding, coalescing: Duration = .milliseconds(40)) {
        self.provider = provider
        self.coalescing = coalescing
    }

    public var source: ForecastSource { provider.source }

    /// Swap the provider (Sample Data mode) and drop everything fetched with the old one.
    public func replaceProvider(_ provider: any WeatherProviding) {
        self.provider = provider
        dropInFlight()
        states = [:]
        lastGood = [:]
        failedKeys = []
        status = .ok
        revision += 1
    }

    /// Drops every state and in-flight fetch but keeps the provider (its settings or keys changed), so screens refetch.
    public func invalidateAll() {
        dropInFlight()
        states = [:]
        failedKeys = []
        status = .ok
        revision += 1
    }

    private func dropInFlight() {
        inFlight.values.forEach { $0.cancel() }
        inFlight = [:]
        pending = []
        flushTask?.cancel()
        flushTask = nil
    }

    public func state(for coordinate: Coordinate) -> ForecastState {
        states[coordinate.cacheKey] ?? .loading
    }

    /// Whether a fetch for the place is running right now.
    func isFetching(_ coordinate: Coordinate) -> Bool { inFlight[coordinate.cacheKey] != nil }

    public func isLoading(_ coordinate: Coordinate) -> Bool {
        if case .loading = state(for: coordinate) { return true }
        return false
    }

    /// Starts a fetch if there is no state yet (or `force`). Returns immediately. A fetch already running for the
    /// place is joined, forced or not: a second one would race the first and orphan its task.
    public func request(_ coordinate: Coordinate, force: Bool = false) {
        let key = coordinate.cacheKey
        if inFlight[key] != nil { return }
        if !force, states[key] != nil && !seededKeys.contains(key) { return }
        seededKeys.remove(key)
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
                // Cancelled by `invalidateAll` or `replaceProvider`, which already cleared this fetch. A provider that
                // threw it on its own would otherwise leave the place waiting on a finished task for good.
                if !Task.isCancelled, let self { self.abandon(key: key) }
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

    /// A fetch ended without a result and without being cancelled by the centre: forget it so the place can be asked again.
    private func abandon(key: String) {
        inFlight[key] = nil
        if case .loading? = states[key] { states[key] = nil }
        if inFlight.isEmpty { flush() }
    }

    private func finish(key: String, _ result: FetchResult) {
        inFlight[key] = nil
        pending.append((key, result))
        IterPerf.count("forecast.finish")
        if inFlight.isEmpty {
            flush()
        } else if flushTask == nil {
            let wait = coalescing
            flushTask = Task { [weak self] in
                try? await Task.sleep(for: wait)
                guard !Task.isCancelled else { return }
                self?.flush()
            }
        }
    }

    /// Applies every finished fetch in the order they ended, then bumps `revision` once if anything on screen changed.
    private func flush() {
        flushTask?.cancel()
        flushTask = nil
        guard !pending.isEmpty else { return }
        let batch = pending
        pending = []
        var changed = false
        for (key, result) in batch { changed = apply(key: key, result) || changed }
        if changed {
            revision += 1
            IterPerf.count("forecast.bump")
        }
        if inFlight.isEmpty { IterPerf.mark("forecast.idle", "states=\(states.count) applied=\(batch.count) changed=\(changed)") }
    }

    /// Whether the result changed what is shown (a state, or the status banner).
    private func apply(key: String, _ result: FetchResult) -> Bool {
        var changed = false
        func show(_ state: ForecastState) {
            if states[key] != state { states[key] = state; changed = true }
        }
        func setStatus(_ new: WeatherStatus) {
            if status != new { status = new; changed = true }
        }
        switch result {
        case .success(let forecast):
            if lastGood[key] != forecast { lastGood[key] = forecast }
            failedKeys.remove(key)
            show(.loaded(forecast))
            setStatus(.ok)
        case .failure(let reason):
            show(lastGood[key].map { .loaded($0) } ?? .unavailable(reason))
            switch reason {
            case .inThePast, .beyondHorizon, .notLoaded:
                break
            default:
                failedKeys.insert(key)
                let last = lastGood.values.map(\.fetchedAt).max()
                switch reason {
                case .missingAPIKey(let source): setStatus(.needsKey(source))
                case .offline(let source): setStatus(.offline(source, lastUpdate: last))
                default: setStatus(.failed(reason, lastUpdate: last))
                }
            }
        }
        return changed
    }

    /// Puts a saved forecast (from an offline pack) on screen: kept as the last good one when newer, and shown when
    /// there is nothing better. A later ordinary request still tries the network and falls back to it.
    public func seed(_ forecast: Forecast, for coordinate: Coordinate) {
        let key = coordinate.cacheKey
        if (lastGood[key]?.fetchedAt ?? .distantPast) < forecast.fetchedAt { lastGood[key] = forecast }
        // Something already on screen for the place stays; only a place with nothing to show changes, so only then bump.
        guard states[key]?.forecast == nil, let best = lastGood[key] else { return }
        if inFlight[key] == nil { seededKeys.insert(key) }
        states[key] = .loaded(best)
        revision += 1
    }

    /// Forces a fetch (or joins the one running) and waits. Check `didFail` to tell a fresh forecast from the last-good fallback.
    public func refresh(_ coordinate: Coordinate) async -> ForecastState {
        let key = coordinate.cacheKey
        if inFlight[key] == nil { request(coordinate, force: true) }
        await inFlight[key]?.value
        flush()
        return state(for: coordinate)
    }

    /// Whether the latest fetch for this place failed (the state then shows the last good forecast, if any).
    public func didFail(_ coordinate: Coordinate) -> Bool { failedKeys.contains(coordinate.cacheKey) }

    public func requestAll(_ coordinates: [Coordinate]) {
        for c in coordinates { request(c) }
    }

    /// Fetch and wait (for tests and the smoke hook).
    public func load(_ coordinate: Coordinate) async -> ForecastState {
        request(coordinate)
        await inFlight[coordinate.cacheKey]?.value
        flush()
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
