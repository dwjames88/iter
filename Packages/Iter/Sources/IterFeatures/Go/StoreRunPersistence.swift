import Foundation
import IterGo
import IterStore

/// Persists trip runs through `LibraryStore.runs` (`RunRepository`) and nothing else: no `ModelContext` is touched here.
///
/// **Run id.** The engine creates its `TripRun` with its own id, but `RunRepository.createRun(forTrip:state:)` makes the record
/// with a fresh id and `TripRunRecord.init(id:)` is not reachable through the repository. So the two ids differ and this class
/// keeps the mapping in one small JSON file per run, `go-run-<recordID>.json`, in `directory` (Application Support in the app):
/// the engine run id, the sidecar (`pausedFrom`, `pendingUndo`, `suppressions`, which the store has no column for) and the
/// engine's `startedAt`/`endedAt` (the store sets its own from its clock). `activeRun` reads the file to give the engine back
/// its own id; visits are stored under the record id. An additive `createRun(id:)` in IterStore would remove the mapping.
///
/// **Lossy case.** `RunRepository.upsertVisit` cannot clear a date: when "Not yet" undoes a transition and a visit's `arrivedAt`
/// or `leftAt` goes back to nil, the stored date stays. The status is always right and a restored run derives its phase from
/// status alone, so only the history view could show a stale date.
@MainActor
public final class StoreRunPersistence: RunPersisting {
    /// What sits beside a run in the store.
    struct RunFile: Codable, Equatable {
        var engineRunID: UUID
        var startedAt: Date?
        var endedAt: Date?
        var sidecar: RunSidecar?
    }

    private let store: LibraryStore
    private let directory: URL
    /// Engine run id to record id.
    private var recordIDs: [UUID: UUID] = [:]

    public init(store: LibraryStore, directory: URL) {
        self.store = store
        self.directory = directory
    }

    // MARK: RunPersisting

    public func activeRun(tripID: UUID) -> PersistedRun? {
        guard let record = store.runs.activeRun(forTrip: tripID) else { return nil }
        let file = readFile(recordID: record.id)
        let engineID = file?.engineRunID ?? record.id
        recordIDs[engineID] = record.id
        let visits = store.runs.visits(forRun: record.id).map {
            PersistedVisit(stopID: $0.stopID, statusRaw: $0.statusRaw, departedForAt: $0.departedForAt, arrivedAt: $0.arrivedAt,
                           leftAt: $0.leftAt, plannedLeaveBy: $0.plannedLeaveBy, plannedArrival: $0.plannedArrival)
        }
        return PersistedRun(id: engineID, tripID: record.tripID, stateRaw: record.stateRaw, startedAt: file?.startedAt ?? record.startedAt,
                            endedAt: file?.endedAt ?? record.endedAt, currentStopID: record.currentStopID, visits: visits)
    }

    public func save(_ run: PersistedRun) {
        let state = StoredRunState(rawValue: run.stateRaw) ?? .armed
        let record: TripRunRecord
        if let existing = existingRecord(engineRunID: run.id) {
            record = existing
        } else {
            record = store.runs.createRun(forTrip: run.tripID, state: state)
            recordIDs[run.id] = record.id
        }
        store.runs.setState(record, to: state, currentStopID: .some(run.currentStopID))
        var file = readFile(recordID: record.id) ?? RunFile(engineRunID: run.id)
        file.engineRunID = run.id
        file.startedAt = run.startedAt
        file.endedAt = run.endedAt
        writeFile(file, recordID: record.id)
        for visit in run.visits { upsert(visit, recordID: record.id) }
        store.flush()
    }

    public func saveVisit(runID: UUID, _ visit: PersistedVisit) {
        guard let record = existingRecord(engineRunID: runID) else { return }
        upsert(visit, recordID: record.id)
    }

    public func loadSidecar(runID: UUID) -> RunSidecar? {
        guard let record = existingRecord(engineRunID: runID) else { return nil }
        return readFile(recordID: record.id)?.sidecar
    }

    public func saveSidecar(_ sidecar: RunSidecar?, runID: UUID) {
        guard let record = existingRecord(engineRunID: runID) else { return }
        var file = readFile(recordID: record.id) ?? RunFile(engineRunID: runID)
        file.sidecar = sidecar
        writeFile(file, recordID: record.id)
        store.flush()
    }

    // MARK: Mapping

    private func upsert(_ visit: PersistedVisit, recordID: UUID) {
        let status = StoredVisitStatus(rawValue: visit.statusRaw) ?? .pending
        store.runs.upsertVisit(runID: recordID, stopID: visit.stopID,
                               StopVisitUpdate(status: status, departedForAt: visit.departedForAt, arrivedAt: visit.arrivedAt,
                                               leftAt: visit.leftAt, plannedLeaveBy: visit.plannedLeaveBy, plannedArrival: visit.plannedArrival))
    }

    private func existingRecord(engineRunID: UUID) -> TripRunRecord? {
        if let id = recordIDs[engineRunID], let record = store.runs.run(id: id) { return record }
        // After a relaunch the cache is empty until `activeRun`; a stray call finds the record by its file.
        for url in files() {
            guard let data = try? Data(contentsOf: url), let file = try? JSONDecoder().decode(RunFile.self, from: data),
                  file.engineRunID == engineRunID, let recordID = Self.recordID(of: url), let record = store.runs.run(id: recordID) else { continue }
            recordIDs[engineRunID] = recordID
            return record
        }
        return nil
    }

    // MARK: Files

    private static let prefix = "go-run-"

    func fileURL(recordID: UUID) -> URL { directory.appendingPathComponent("\(Self.prefix)\(recordID.uuidString).json") }

    private static func recordID(of url: URL) -> UUID? {
        let name = url.deletingPathExtension().lastPathComponent
        guard name.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(name.dropFirst(prefix.count)))
    }

    private func files() -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasPrefix(Self.prefix) && $0.pathExtension == "json" }
    }

    private func readFile(recordID: UUID) -> RunFile? {
        guard let data = try? Data(contentsOf: fileURL(recordID: recordID)) else { return nil }
        return try? JSONDecoder().decode(RunFile.self, from: data)
    }

    private func writeFile(_ file: RunFile, recordID: UUID) {
        guard let data = try? JSONEncoder().encode(file) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: fileURL(recordID: recordID), options: .atomic)
    }
}
