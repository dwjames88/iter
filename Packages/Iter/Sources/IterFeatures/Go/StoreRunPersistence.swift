import Foundation
import IterGo
import IterStore

/// Persists trip runs through `LibraryStore.runs` (`RunRepository`) and nothing else: no `ModelContext` is touched here.
///
/// The store record has the engine's run id, its start and end times and its visits' dates exactly as the engine holds them
/// (a "Not yet" that undoes an arrival clears `arrivedAt` in the store), so there is no id mapping.
///
/// **The one file per run.** `pausedFrom`, `pendingUndo` and `suppressions` (`RunSidecar`) have no column in the store, so
/// they sit in `go-sidecar-<run id>.json` in `directory` (Application Support in the app): the sidecar and nothing else.
/// It lets a relaunch resume "Not yet" and the suppressions. A `go-run-*.json` file from an earlier build is never read.
@MainActor
public final class StoreRunPersistence: RunPersisting {
    private let store: LibraryStore
    private let directory: URL

    public init(store: LibraryStore, directory: URL) {
        self.store = store
        self.directory = directory
    }

    // MARK: RunPersisting

    public func activeRun(tripID: UUID) -> PersistedRun? {
        guard let record = store.runs.activeRun(forTrip: tripID) else { return nil }
        let visits = store.runs.visits(forRun: record.id).map {
            PersistedVisit(stopID: $0.stopID, statusRaw: $0.statusRaw, departedForAt: $0.departedForAt, arrivedAt: $0.arrivedAt,
                           leftAt: $0.leftAt, plannedLeaveBy: $0.plannedLeaveBy, plannedArrival: $0.plannedArrival)
        }
        return PersistedRun(id: record.id, tripID: record.tripID, stateRaw: record.stateRaw, startedAt: record.startedAt,
                            endedAt: record.endedAt, currentStopID: record.currentStopID, visits: visits)
    }

    public func save(_ run: PersistedRun) {
        let state = StoredRunState(rawValue: run.stateRaw) ?? .armed
        if let record = store.runs.run(id: run.id) {
            store.runs.restore(record, state: state, currentStopID: run.currentStopID, startedAt: run.startedAt, endedAt: run.endedAt)
        } else {
            let record = store.runs.createRun(id: run.id, forTrip: run.tripID, state: state, startedAt: run.startedAt, endedAt: run.endedAt)
            record.currentStopID = run.currentStopID
        }
        for visit in run.visits { upsert(visit, runID: run.id) }
        store.flush()
    }

    public func saveVisit(runID: UUID, _ visit: PersistedVisit) {
        guard store.runs.run(id: runID) != nil else { return }
        upsert(visit, runID: runID)
    }

    public func loadSidecar(runID: UUID) -> RunSidecar? {
        guard let data = try? Data(contentsOf: fileURL(runID: runID)) else { return nil }
        return try? JSONDecoder().decode(RunSidecar.self, from: data)
    }

    public func saveSidecar(_ sidecar: RunSidecar?, runID: UUID) {
        guard store.runs.run(id: runID) != nil else { return }
        guard let sidecar else {
            try? FileManager.default.removeItem(at: fileURL(runID: runID))
            return
        }
        guard let data = try? JSONEncoder().encode(sidecar) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: fileURL(runID: runID), options: .atomic)
    }

    // MARK: Mapping

    private func upsert(_ visit: PersistedVisit, runID: UUID) {
        let status = StoredVisitStatus(rawValue: visit.statusRaw) ?? .pending
        store.runs.upsertVisit(runID: runID, stopID: visit.stopID,
                               .exact(status: status, departedForAt: visit.departedForAt, arrivedAt: visit.arrivedAt, leftAt: visit.leftAt,
                                      plannedLeaveBy: visit.plannedLeaveBy, plannedArrival: visit.plannedArrival))
    }

    func fileURL(runID: UUID) -> URL { directory.appendingPathComponent("go-sidecar-\(runID.uuidString).json") }
}
