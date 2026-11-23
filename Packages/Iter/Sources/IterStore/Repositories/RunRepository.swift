import Foundation
import SwiftData

/// The stored state of a trip-mode run. The run state machine itself lives in IterGo; this is its persistence.
public enum StoredRunState: String, Sendable, CaseIterable {
    case armed, active, paused, finished
}

/// The stored progress through one stop of a run.
public enum StoredVisitStatus: String, Sendable, CaseIterable {
    case pending, enRoute, arrived, done, skipped
}

/// The dates of a visit, for `StopVisitUpdate.clearing`.
public enum StopVisitDate: Sendable, CaseIterable {
    case departedForAt, arrivedAt, leftAt, plannedLeaveBy, plannedArrival
}

/// What to change on a visit; nil fields are left as they are, except the dates named in `clearing`, which are set to nil
/// (a date that has a value is set, whatever `clearing` says). That is the "leave / set / clear" choice per date, and it keeps
/// every existing call site source-compatible.
public struct StopVisitUpdate: Sendable {
    public var status: StoredVisitStatus?
    public var departedForAt: Date?
    public var arrivedAt: Date?
    public var leftAt: Date?
    public var plannedLeaveBy: Date?
    public var plannedArrival: Date?
    public var clearing: Set<StopVisitDate>

    /// Writes exactly the given dates: each nil date is cleared, not left. Used to mirror a run engine's visit.
    public static func exact(status: StoredVisitStatus, departedForAt: Date?, arrivedAt: Date?, leftAt: Date?,
                             plannedLeaveBy: Date?, plannedArrival: Date?) -> StopVisitUpdate {
        var clearing = Set<StopVisitDate>()
        if departedForAt == nil { clearing.insert(.departedForAt) }
        if arrivedAt == nil { clearing.insert(.arrivedAt) }
        if leftAt == nil { clearing.insert(.leftAt) }
        if plannedLeaveBy == nil { clearing.insert(.plannedLeaveBy) }
        if plannedArrival == nil { clearing.insert(.plannedArrival) }
        return StopVisitUpdate(status: status, departedForAt: departedForAt, arrivedAt: arrivedAt, leftAt: leftAt,
                               plannedLeaveBy: plannedLeaveBy, plannedArrival: plannedArrival, clearing: clearing)
    }

    public init(status: StoredVisitStatus? = nil, departedForAt: Date? = nil, arrivedAt: Date? = nil, leftAt: Date? = nil,
                plannedLeaveBy: Date? = nil, plannedArrival: Date? = nil, clearing: Set<StopVisitDate> = []) {
        self.clearing = clearing
        self.status = status
        self.departedForAt = departedForAt
        self.arrivedAt = arrivedAt
        self.leftAt = leftAt
        self.plannedLeaveBy = plannedLeaveBy
        self.plannedArrival = plannedArrival
    }
}

/// Minimal CRUD for trip-mode runs and visits. Not undoable: a run is a log of what happened, not an edit.
@MainActor
public struct RunRepository {
    unowned let store: LibraryStore

    public func run(id: UUID) -> TripRunRecord? {
        var descriptor = FetchDescriptor<TripRunRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? store.context.fetch(descriptor).first
    }

    /// The runs of a trip, most recently changed first.
    public func runs(forTrip tripID: UUID) -> [TripRunRecord] {
        let all = (try? store.context.fetch(FetchDescriptor<TripRunRecord>(predicate: #Predicate { $0.tripID == tripID }))) ?? []
        return all.sorted { ($0.updatedAt, $0.id.uuidString) > ($1.updatedAt, $1.id.uuidString) }
    }

    /// The run of a trip that has not finished (armed, active or paused), the most recently changed if several.
    public func activeRun(forTrip tripID: UUID) -> TripRunRecord? {
        runs(forTrip: tripID).first { $0.stateRaw != StoredRunState.finished.rawValue }
    }

    @discardableResult
    public func createRun(forTrip tripID: UUID, state: StoredRunState = .armed) -> TripRunRecord {
        createRun(id: UUID(), forTrip: tripID, state: state)
    }

    /// Creates the run with the caller's id (the run engine's), so the record and the engine agree. `startedAt` and
    /// `endedAt`, when given, are the engine's times and replace the store's own stamps.
    @discardableResult
    public func createRun(id: UUID, forTrip tripID: UUID, state: StoredRunState = .armed, startedAt: Date? = nil,
                          endedAt: Date? = nil) -> TripRunRecord {
        let run = TripRunRecord(id: id)
        store.context.insert(run)
        run.tripID = tripID
        run.stateRaw = state.rawValue
        let now = store.clock()
        if state == .active { run.startedAt = now }
        if let startedAt { run.startedAt = startedAt }
        run.endedAt = endedAt
        run.updatedAt = now
        store.didChange()
        return run
    }

    /// Sets state, current stop and the start and end times to exactly the given values (nil clears). For mirroring a run
    /// engine, whose times are the truth; `setState` stamps the store's own clock instead.
    public func restore(_ run: TripRunRecord, state: StoredRunState, currentStopID: UUID?, startedAt: Date?, endedAt: Date?) {
        run.stateRaw = state.rawValue
        run.currentStopID = currentStopID
        run.startedAt = startedAt
        run.endedAt = endedAt
        run.updatedAt = store.clock()
        store.didChange()
    }

    /// Sets the state. The first time a run goes active it gets `startedAt`; finishing sets `endedAt`.
    public func setState(_ run: TripRunRecord, to state: StoredRunState, currentStopID: UUID?? = nil) {
        let now = store.clock()
        run.stateRaw = state.rawValue
        if state == .active, run.startedAt == nil { run.startedAt = now }
        if state == .finished { run.endedAt = now }
        if let currentStopID { run.currentStopID = currentStopID }
        run.updatedAt = now
        store.didChange()
    }

    public func visits(forRun runID: UUID) -> [StopVisitRecord] {
        let all = (try? store.context.fetch(FetchDescriptor<StopVisitRecord>(predicate: #Predicate { $0.runID == runID }))) ?? []
        return all.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    public func visit(runID: UUID, stopID: UUID) -> StopVisitRecord? {
        var descriptor = FetchDescriptor<StopVisitRecord>(predicate: #Predicate { $0.runID == runID && $0.stopID == stopID })
        descriptor.fetchLimit = 1
        return try? store.context.fetch(descriptor).first
    }

    /// The visit of `stopID` in the run, created pending if there is none, with `update` applied.
    @discardableResult
    public func upsertVisit(runID: UUID, stopID: UUID, _ update: StopVisitUpdate = StopVisitUpdate()) -> StopVisitRecord {
        let visit = self.visit(runID: runID, stopID: stopID) ?? {
            let new = StopVisitRecord()
            store.context.insert(new)
            new.runID = runID
            new.stopID = stopID
            return new
        }()
        if let status = update.status { visit.statusRaw = status.rawValue }
        if let date = update.departedForAt { visit.departedForAt = date }
        if let date = update.arrivedAt { visit.arrivedAt = date }
        if let date = update.leftAt { visit.leftAt = date }
        if let date = update.plannedLeaveBy { visit.plannedLeaveBy = date }
        if let date = update.plannedArrival { visit.plannedArrival = date }
        for date in update.clearing {
            switch date {
            case .departedForAt: if update.departedForAt == nil { visit.departedForAt = nil }
            case .arrivedAt: if update.arrivedAt == nil { visit.arrivedAt = nil }
            case .leftAt: if update.leftAt == nil { visit.leftAt = nil }
            case .plannedLeaveBy: if update.plannedLeaveBy == nil { visit.plannedLeaveBy = nil }
            case .plannedArrival: if update.plannedArrival == nil { visit.plannedArrival = nil }
            }
        }
        visit.updatedAt = store.clock()
        store.didChange()
        return visit
    }
}
