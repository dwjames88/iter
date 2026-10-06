import Foundation
import Observation
import IterCore
import IterServices

/// Why a scout run produced no places. The app phrases each case.
public enum ScoutFailure: Hashable, Sendable {
    case unavailable(ScoutAvailability)
    case noResults
    case guardrail
    case tooLong
    case unsupportedLanguage
    case failed(String)

    init(_ error: ScoutError) {
        switch error {
        case .unavailable(let a): self = .unavailable(a)
        case .noResults: self = .noResults
        case .guardrail: self = .guardrail
        case .contextTooLong: self = .tooLong
        case .unsupportedLanguage: self = .unsupportedLanguage
        case .failed(let detail): self = .failed(detail)
        }
    }
}

/// The light for a scouted place: its next sunrise or sunset. Never a number without a forecast.
public enum ScoutLight: Equatable, Sendable {
    /// The next event; the window is unscored when there is no data (the screen shows one banner for that).
    case window(day: LocalDay, window: LightWindow)
    /// The spot has no sunrise or sunset event ahead.
    case none
    /// The forecast is still being fetched.
    case loading
}

public enum ScoutState: Equatable, Sendable {
    case idle
    case running(stage: ScoutProgress, started: Date)
    case results([ScoutSuggestion])
    case failed(ScoutFailure)
}

/// The scout screen's state machine: request text, running with real stages, results, failure, cancellation.
@MainActor
@Observable
public final class ScoutModel {
    public var request = ""
    public private(set) var state: ScoutState = .idle
    /// The text that produced the current results or failure (the field may have been edited since).
    public private(set) var submittedRequest = ""

    @ObservationIgnored private let app: AppModel
    @ObservationIgnored private let scout: (any Scouting)?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    public init(app: AppModel, scout: (any Scouting)? = nil, state: ScoutState = .idle, request: String = "") {
        self.app = app
        self.scout = scout ?? app.scout
        self.state = state
        self.request = request
        self.submittedRequest = request
    }

    private static var sessions: [ObjectIdentifier: ScoutModel] = [:]

    /// One scout session per app model, so switching sidebar sections neither loses results nor drops a running request.
    public static func session(for app: AppModel) -> ScoutModel {
        let key = ObjectIdentifier(app)
        if let existing = sessions[key] { return existing }
        let created = ScoutModel(app: app)
        sessions[key] = created
        return created
    }

    // MARK: Availability

    public var availability: ScoutAvailability {
        scout?.availability() ?? .unavailable("Apple Intelligence is not part of this build.")
    }

    public var canRun: Bool {
        guard !request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if case .running = state { return false }
        return true
    }

    public var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    // MARK: Running

    public func run() {
        let text = request.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isRunning else { return }
        guard let scout else { state = .failed(.unavailable(availability)); return }
        let availability = scout.availability()
        guard availability == .available else { state = .failed(.unavailable(availability)); return }

        generation += 1
        let mine = generation
        submittedRequest = text
        state = .running(stage: .understanding, started: app.now())
        let report: @Sendable (ScoutProgress) -> Void = { [weak self] progress in
            Task { @MainActor in self?.advance(to: progress, generation: mine) }
        }
        task = Task { [weak self] in
            do {
                let found = try await scout.scout(text, progress: report)
                self?.finish(.results(found), generation: mine, found: found)
            } catch is CancellationError {
                self?.cancelled(generation: mine)
            } catch let error as ScoutError {
                self?.finish(.failed(ScoutFailure(error)), generation: mine, found: [])
            } catch {
                self?.finish(.failed(.failed(String(describing: error))), generation: mine, found: [])
            }
        }
    }

    /// Stops the running request. The field keeps its text so it can be edited and run again.
    public func cancel() {
        guard isRunning else { return }
        generation += 1
        task?.cancel()
        task = nil
        state = .idle
    }

    /// Back to the empty field (clears results or an error).
    public func reset() {
        cancel()
        state = .idle
    }

    private func advance(to progress: ScoutProgress, generation: Int) {
        guard generation == self.generation, case .running(_, let started) = state else { return }
        state = .running(stage: progress, started: started)
    }

    private func finish(_ outcome: ScoutState, generation: Int, found: [ScoutSuggestion]) {
        guard generation == self.generation else { return }
        task = nil
        if case .results(let list) = outcome, list.isEmpty {
            state = .failed(.noResults)
            return
        }
        state = outcome
        app.forecasts.requestAll(found.map(\.spot.coordinate))
    }

    private func cancelled(generation: Int) {
        guard generation == self.generation else { return }
        task = nil
        state = .idle
    }

    // MARK: Scoring

    /// The next sunrise or sunset at the place, scored by the engine from the forecast, or unscored without one.
    public func light(for suggestion: ScoutSuggestion) -> ScoutLight {
        _ = app.forecasts.revision
        let spot = suggestion.spot
        app.forecasts.request(spot.coordinate)
        if app.forecasts.isLoading(spot.coordinate) { return .loading }
        guard let next = app.nextLight(for: spot) else { return .none }
        return .window(day: next.day, window: next.window)
    }
}
