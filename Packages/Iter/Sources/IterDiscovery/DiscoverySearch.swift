import Foundation
import IterModel
import Observation

/// The UI-facing controller for Find. One instance per search surface.
///
/// `search(_:)` cancels the previous run, takes a new generation number, and applies only events carrying the current
/// generation, so a slow old search can never overwrite a newer one (ported from the Search Here guard).
@MainActor
@Observable
public final class DiscoverySearch {
    public enum Phase: Equatable, Sendable {
        case idle
        case planning
        case resolvingArea
        case searching
        case finished
        /// The run could not search at all; the text is ready to show.
        case failed(String)
        case cancelled
    }

    public private(set) var phase: Phase = .idle
    public private(set) var places: [DiscoveredPlace] = []
    public private(set) var statuses: [SourceStatus] = []
    public private(set) var plan: QueryPlan?
    public private(set) var planOrigin: PlanOrigin?
    public private(set) var area: ResolvedArea?
    public private(set) var result: DiscoveryResult?

    /// Incremented by every `search` and `cancel`; events from an older generation are dropped.
    public private(set) var generation = 0

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private let engine: DiscoveryEngine

    public init(engine: DiscoveryEngine) {
        self.engine = engine
    }

    /// "Basic search: AI unavailable (...)" when the plan came from the deterministic parser, else nil.
    public var basicSearchLabel: String? { planOrigin?.label }

    /// Starts a search, cancelling any run in flight.
    public func search(_ request: DiscoveryRequest) {
        task?.cancel()
        generation += 1
        let mine = generation
        phase = .planning
        places = []
        statuses = []
        plan = nil
        planOrigin = nil
        area = nil
        result = nil
        let stream = engine.run(request)
        task = Task { [weak self] in
            for await event in stream {
                guard let self, self.generation == mine, !Task.isCancelled else { return }
                self.apply(event)
            }
        }
    }

    /// Stops the current run and ignores anything it still sends.
    public func cancel() {
        task?.cancel()
        task = nil
        generation += 1
        if phase != .finished, phase != .idle { phase = .cancelled }
    }

    private func apply(_ event: DiscoveryEvent) {
        switch event {
        case .planReady(let p, let origin):
            plan = p
            planOrigin = origin
            phase = .resolvingArea
        case .areaResolved(let a):
            area = a
            phase = .searching
        case .statusChanged(let s):
            if let i = statuses.firstIndex(where: { $0.source == s.source }) { statuses[i] = s } else { statuses.append(s) }
        case .partial(let list):
            places = list
        case .finished(let r):
            result = r
            places = r.places
            statuses = r.statuses
            plan = r.plan
            planOrigin = r.planOrigin
            area = r.area
            phase = r.failure.map { .failed($0.description) } ?? .finished
        }
    }
}
