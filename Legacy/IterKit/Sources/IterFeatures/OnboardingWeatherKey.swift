import Foundation
import Observation
import IterCore
import IterServices

/// Checks an OpenWeather key as it is typed or pasted: shape first (no network), then one real call with that key.
@MainActor
@Observable
public final class OpenWeatherKeyCheck {
    public enum State: Equatable, Sendable {
        case idle
        case invalidFormat
        case checking
        case working
        case failed(WeatherError)
    }

    /// Tests the candidate key with one call; throws `WeatherError` (or anything, shown as a provider error).
    public typealias Probe = @Sendable (String) async throws -> Void

    public private(set) var state: State = .idle
    /// The trimmed text of the key field.
    public private(set) var draft = ""

    @ObservationIgnored private let probe: Probe
    @ObservationIgnored private let debounce: Duration
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    public init(debounce: Duration = .milliseconds(500), probe: @escaping Probe = OpenWeatherKeyCheck.liveProbe()) {
        self.debounce = debounce
        self.probe = probe
    }

    /// OpenWeather keys are 32 hexadecimal characters.
    public static func isWellFormed(_ key: String) -> Bool {
        key.count == 32 && key.allSatisfy(\.isHexDigit) && key.allSatisfy(\.isASCII)
    }

    /// The text of the key field changed. Replaces any check in flight.
    public func update(draft text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != draft else { return }
        draft = trimmed
        task?.cancel()
        generation += 1
        if trimmed.isEmpty { state = .idle; return }
        guard Self.isWellFormed(trimmed) else { state = .invalidFormat; return }
        state = .checking
        let mine = generation, key = trimmed, probe = probe, debounce = debounce
        task = Task { [weak self] in
            do {
                try await Task.sleep(for: debounce)
                try await probe(key)
                self?.finish(mine, .working)
            } catch is CancellationError {
            } catch let error as WeatherError {
                self?.finish(mine, .failed(error))
            } catch {
                self?.finish(mine, .failed(.provider(.openWeather, String(describing: type(of: error)))))
            }
        }
    }

    private func finish(_ mine: Int, _ result: State) {
        guard mine == generation else { return }
        state = result
    }

    /// Waits for the check in flight (tests).
    public func settled() async { await task?.value }

    /// Whether a draft can be saved: it works, or it was rejected (a new key may just not be active yet).
    public var canSave: Bool {
        switch state {
        case .working, .failed(.keyRejected): true
        default: false
        }
    }

    public var isRejected: Bool {
        if case .failed(.keyRejected) = state { return true }
        return false
    }

    /// Whether a key for OpenWeather is already in use (Keychain, or an environment or launch override).
    public func hasSavedKey(in setup: WeatherSetup) -> Bool { setup.hasKey(for: .openWeather) }

    /// Stores the draft in the key store and makes OpenWeather the primary source.
    public func save(into setup: WeatherSetup) throws {
        guard Self.isWellFormed(draft) else { return }
        try setup.setKey(draft, for: .openWeather)
        setup.selectPrimary(.openWeather)
    }

    // MARK: The real probe

    /// One OpenWeather call with exactly the candidate key: its own in-memory key store, no cache, no cap. Never
    /// reads or writes the saved key or the app's forecast cache.
    public static func liveProbe(transport: any HTTPTransport = URLSessionTransport()) -> Probe {
        { key in
            let keys = APIKeyResolver(store: InMemoryAPIKeyStore([.openWeather: key]), environment: { [:] }, launchArgument: { _ in nil })
            let scratch = UserDefaults(suiteName: "com.dwjames.iter.keyprobe") ?? .standard
            let service = OpenWeatherService(keys: keys, transport: transport,
                                            cache: ProviderCache(directory: nil, validity: .interval(0)),
                                            budget: CallBudget(defaults: scratch, caps: [:]))
            _ = try await service.forecast(for: WeatherSetup.probeCoordinate)
        }
    }
}
