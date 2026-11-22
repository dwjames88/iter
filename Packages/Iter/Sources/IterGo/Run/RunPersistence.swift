import Foundation
import IterGoActivity

// The persistence boundary. IterGo does not depend on IterStore: these are plain mirrors of `TripRunRecord` and
// `StopVisitRecord`, and an adapter in IterFeatures maps them to `RunRepository`.

/// Raw values of `StoredRunState`.
public enum PersistedRunState: String, Codable, Hashable, Sendable, CaseIterable {
    case armed, active, paused, finished
}

/// Mirrors `StopVisitRecord`. The adapter keys it by (runID, stopID).
public struct PersistedVisit: Codable, Hashable, Sendable {
    public var stopID: UUID
    /// A `VisitStatus` raw value (equal to `StoredVisitStatus`).
    public var statusRaw: String
    public var departedForAt: Date?
    public var arrivedAt: Date?
    public var leftAt: Date?
    public var plannedLeaveBy: Date?
    public var plannedArrival: Date?

    public init(stopID: UUID, statusRaw: String, departedForAt: Date? = nil, arrivedAt: Date? = nil, leftAt: Date? = nil,
                plannedLeaveBy: Date? = nil, plannedArrival: Date? = nil) {
        self.stopID = stopID
        self.statusRaw = statusRaw
        self.departedForAt = departedForAt
        self.arrivedAt = arrivedAt
        self.leftAt = leftAt
        self.plannedLeaveBy = plannedLeaveBy
        self.plannedArrival = plannedArrival
    }

    public init(_ visit: StopVisit) {
        self.init(stopID: visit.stopID, statusRaw: visit.status.rawValue, departedForAt: visit.departedForAt,
                  arrivedAt: visit.arrivedAt, leftAt: visit.leftAt, plannedLeaveBy: visit.plannedLeaveBy,
                  plannedArrival: visit.plannedArrival)
    }

    public var visit: StopVisit {
        StopVisit(stopID: stopID, status: VisitStatus(rawValue: statusRaw) ?? .pending, departedForAt: departedForAt,
                  arrivedAt: arrivedAt, leftAt: leftAt, plannedLeaveBy: plannedLeaveBy, plannedArrival: plannedArrival)
    }
}

/// Mirrors `TripRunRecord` plus its visits.
public struct PersistedRun: Codable, Hashable, Sendable {
    public var id: UUID
    public var tripID: UUID
    /// A `PersistedRunState` raw value.
    public var stateRaw: String
    public var startedAt: Date?
    public var endedAt: Date?
    public var currentStopID: UUID?
    public var visits: [PersistedVisit]

    public init(id: UUID, tripID: UUID, stateRaw: String, startedAt: Date? = nil, endedAt: Date? = nil, currentStopID: UUID? = nil,
                visits: [PersistedVisit] = []) {
        self.id = id
        self.tripID = tripID
        self.stateRaw = stateRaw
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.currentStopID = currentStopID
        self.visits = visits
    }
}

/// What the store does not hold: kept beside the run so a relaunch can resume "Not yet" and the suppressions.
public struct RunSidecar: Codable, Hashable, Sendable {
    public var pausedFrom: GoPhase?
    public var pendingUndo: PendingUndo?
    public var suppressions: [RunSuppression]

    public init(pausedFrom: GoPhase? = nil, pendingUndo: PendingUndo? = nil, suppressions: [RunSuppression] = []) {
        self.pausedFrom = pausedFrom
        self.pendingUndo = pendingUndo
        self.suppressions = suppressions
    }
}

@MainActor
public protocol RunPersisting: AnyObject {
    /// The run of a trip that has not finished (armed, active or paused).
    func activeRun(tripID: UUID) -> PersistedRun?
    /// Inserts or updates the run header and upserts the visits it carries; visits it does not carry are left alone.
    func save(_ run: PersistedRun)
    /// Inserts or replaces one visit.
    func saveVisit(runID: UUID, _ visit: PersistedVisit)
    func loadSidecar(runID: UUID) -> RunSidecar?
    /// nil removes it.
    func saveSidecar(_ sidecar: RunSidecar?, runID: UUID)
}

extension RunPersisting {
    /// Persists exactly what a handled event changed: the run header, each changed visit and the sidecar.
    public func record(_ run: TripRun, transitions: [RunTransition]) {
        var header = run.persisted
        header.visits = []
        save(header)
        for visit in transitions.flatMap(\.visitChanges) { saveVisit(runID: run.id, PersistedVisit(visit)) }
        saveSidecar(run.sidecar, runID: run.id)
    }
}

/// Holds runs in memory, for tests and previews.
@MainActor
public final class InMemoryRunPersistence: RunPersisting {
    public private(set) var runs: [UUID: PersistedRun] = [:]
    public private(set) var sidecars: [UUID: RunSidecar] = [:]

    public init() {}

    public func activeRun(tripID: UUID) -> PersistedRun? {
        runs.values.filter { $0.tripID == tripID && $0.stateRaw != PersistedRunState.finished.rawValue }
            .max { ($0.startedAt ?? .distantPast) < ($1.startedAt ?? .distantPast) }
    }

    public func save(_ run: PersistedRun) {
        var merged = runs[run.id]?.visits ?? []
        for visit in run.visits {
            if let i = merged.firstIndex(where: { $0.stopID == visit.stopID }) { merged[i] = visit } else { merged.append(visit) }
        }
        var stored = run
        stored.visits = merged
        runs[run.id] = stored
    }

    public func saveVisit(runID: UUID, _ visit: PersistedVisit) {
        guard var run = runs[runID] else { return }
        if let i = run.visits.firstIndex(where: { $0.stopID == visit.stopID }) { run.visits[i] = visit } else { run.visits.append(visit) }
        runs[runID] = run
    }

    public func loadSidecar(runID: UUID) -> RunSidecar? { sidecars[runID] }

    public func saveSidecar(_ sidecar: RunSidecar?, runID: UUID) { sidecars[runID] = sidecar }
}

extension TripRun {
    /// The store's view of this run. The detailed phase is not stored; `restore` derives it.
    public var persisted: PersistedRun {
        let state: PersistedRunState = switch phase {
        case .finished: .finished
        case .paused: .paused
        case .armed, .idle: .armed
        case .driving, .atStop, .betweenStops: .active
        }
        return PersistedRun(id: id, tripID: tripID, stateRaw: state.rawValue, startedAt: startedAt, endedAt: endedAt,
                            currentStopID: targetStopID,
                            visits: visits.values.map(PersistedVisit.init).sorted { $0.stopID.uuidString < $1.stopID.uuidString })
    }

    /// What the store does not hold; nil when there is nothing to keep.
    public var sidecar: RunSidecar? {
        let s = RunSidecar(pausedFrom: pausedFrom, pendingUndo: pendingUndo, suppressions: suppressions)
        return s.pausedFrom == nil && s.pendingUndo == nil && s.suppressions.isEmpty ? nil : s
    }

    /// Rebuilds a run after a relaunch. The phase is derived: finished, paused and armed map directly; active is driving when
    /// a visit is en route, at a stop when one is arrived, else between stops. An expired pending undo is dropped.
    public static func restore(from persisted: PersistedRun, sidecar: RunSidecar?, now: Date) -> TripRun {
        var visits: [UUID: StopVisit] = [:]
        for p in persisted.visits { visits[p.stopID] = p.visit }
        var run = TripRun(id: persisted.id, tripID: persisted.tripID, startedAt: persisted.startedAt, endedAt: persisted.endedAt,
                          targetStopID: persisted.currentStopID, visits: visits)
        switch PersistedRunState(rawValue: persisted.stateRaw) ?? .armed {
        case .finished: run.phase = .finished
        case .armed: run.phase = .armed
        case .paused:
            run.phase = .paused
            run.pausedFrom = sidecar?.pausedFrom ?? derivePhase(visits: visits)
        case .active: run.phase = derivePhase(visits: visits)
        }
        if let undo = sidecar?.pendingUndo, undo.expiresAt > now, run.phase != .finished { run.pendingUndo = undo }
        run.suppressions = sidecar?.suppressions ?? []
        return run
    }
}
