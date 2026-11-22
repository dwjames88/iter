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

/// What to change on a visit; nil fields are left as they are.
public struct StopVisitUpdate: Sendable {
    public var status: StoredVisitStatus?
    public var departedForAt: Date?
    public var arrivedAt: Date?
    public var leftAt: Date?
    public var plannedLeaveBy: Date?
    public var plannedArrival: Date?

    public init(status: StoredVisitStatus? = nil, departedForAt: Date? = nil, arrivedAt: Date? = nil, leftAt: Date? = nil,
                plannedLeaveBy: Date? = nil, plannedArrival: Date? = nil) {
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
        let run = TripRunRecord()
        store.context.insert(run)
        run.tripID = tripID
        run.stateRaw = state.rawValue
        let now = store.clock()
        if state == .active { run.startedAt = now }
        run.updatedAt = now
        store.didChange()
        return run
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
        visit.updatedAt = store.clock()
        store.didChange()
        return visit
    }
}
