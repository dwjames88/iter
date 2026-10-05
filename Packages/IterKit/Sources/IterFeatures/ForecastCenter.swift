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

/// Fetches and holds forecasts per place (keyed by `Coordinate.cacheKey`). Main-actor state, async fetches.
@MainActor
@Observable
public final class ForecastCenter {
    public private(set) var states: [String: ForecastState] = [:]
    /// Bumped whenever any state changes or the provider is swapped, so views can recompute light.
    public private(set) var revision = 0

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
        revision += 1
    }

    public func state(for coordinate: Coordinate) -> ForecastState {
        states[coordinate.cacheKey] ?? .loading
    }

    /// Starts a fetch if there is no state yet (or `force`). Returns immediately.
    public func request(_ coordinate: Coordinate, force: Bool = false) {
        let key = coordinate.cacheKey
        if !force, states[key] != nil || inFlight[key] != nil { return }
        if states[key] == nil { states[key] = .loading }
        let provider = self.provider
        inFlight[key] = Task { [weak self] in
            let result: ForecastState
            do {
                result = .loaded(try await provider.forecast(for: coordinate))
            } catch let error as WeatherError {
                result = .unavailable(error.unavailableReason)
            } catch is CancellationError {
                return
            } catch {
                result = .unavailable(.serviceFailed(detail: String(describing: error)))
            }
            guard !Task.isCancelled, let self else { return }
            self.states[key] = result
            self.inFlight[key] = nil
            self.revision += 1
        }
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
        for (key, state) in states {
            if case .unavailable = state, let c = Self.coordinate(fromKey: key) { request(c, force: true) }
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
