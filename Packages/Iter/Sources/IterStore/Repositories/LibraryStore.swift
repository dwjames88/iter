import Foundation
import Observation
import OSLog
import SwiftData

/// The only way the app changes data. Main-actor, small-data (hundreds of rows). It vends the repositories, which share
/// one transaction and undo mechanism.
///
/// Undo: each mutation snapshots the trips, places, folders and tombstones it touches before and after, and registers
/// an undo on `undoManager` that restores the "before" snapshots (recreating deleted records with the same ids and
/// relationships). The undo registers the redo the same way. The container's context keeps SwiftData's own undo off,
/// otherwise undo would be applied twice.
///
/// Saves: a mutation marks the context dirty and schedules ONE save for the next main-actor turn, so a burst of edits
/// saves once. `flush()` saves now (tests, app termination, export).
@MainActor @Observable
public final class LibraryStore {
    @ObservationIgnored public let container: ModelContainer
    @ObservationIgnored public let context: ModelContext
    /// The window's undo manager. Held weakly; when nil, edits are simply not undoable.
    @ObservationIgnored public weak var undoManager: UndoManager?
    /// Localized undo menu names. The app injects the real ones.
    @ObservationIgnored public var actionName: @MainActor (StoreAction) -> String = { $0.rawValue }
    /// The time source for `updatedAt`, `createdAt`, `pinnedAt` and `deletedAt`. Tests inject a fixed or ticking one.
    @ObservationIgnored public var clock: () -> Date

    /// Incremented after every change (including undo and redo) so view models can observe the store.
    public private(set) var revision = 0
    /// The most recent save failure, if any; cleared by the next successful save.
    @ObservationIgnored public private(set) var lastSaveError: (any Error)?
    /// How many saves reached the context's store (a save with nothing to write does not count).
    @ObservationIgnored public private(set) var saveCount = 0

    @ObservationIgnored var pending: StoreState?
    @ObservationIgnored private var saveScheduled = false
    @ObservationIgnored private let log = Logger(subsystem: "com.dwjames.iter", category: "LibraryStore")

    public init(container: ModelContainer, clock: @escaping () -> Date = { Date() }) {
        self.container = container
        self.clock = clock
        context = container.mainContext
        context.undoManager = nil
        context.autosaveEnabled = false
        _ = try? FolderFlatten.flattenFolders(in: context, now: clock())
    }

    // MARK: - Repositories

    public var trips: TripRepository { TripRepository(store: self) }
    public var places: PlaceRepository { PlaceRepository(store: self) }
    public var folders: FolderRepository { FolderRepository(store: self) }
    public var runs: RunRepository { RunRepository(store: self) }
    public var deletions: DeletionRepository { DeletionRepository(store: self) }

    // MARK: - Saving

    /// Saves now, if anything changed. Used by tests, app termination and export.
    public func flush() {
        saveScheduled = false
        guard context.hasChanges else { return }
        do {
            try context.save()
            saveCount += 1
            lastSaveError = nil
        } catch {
            lastSaveError = error
            log.error("save failed: \(String(describing: error))")
        }
    }

    /// Marks the context dirty and schedules one save for the next main-actor turn.
    func scheduleSave() {
        guard !saveScheduled else { return }
        saveScheduled = true
        Task { @MainActor in
            guard self.saveScheduled else { return }
            self.flush()
        }
    }

    func didChange() {
        scheduleSave()
        revision += 1
    }

    // MARK: - Transaction and undo

    @discardableResult
    func perform<T>(_ action: StoreAction, undoable: Bool = true, _ body: () -> T) -> T {
        precondition(pending == nil, "LibraryStore mutations do not nest")
        pending = StoreState()
        let result = body()
        let before = pending ?? StoreState()
        pending = nil
        didChange()
        if undoable, undoManager != nil {
            var after = StoreState(tripIDs: before.tripIDs, placeIDs: before.placeIDs, folderIDs: before.folderIDs,
                                   tombstoneKeys: before.tombstoneKeys)
            for id in before.tripIDs { if let trip = tripRecord(id: id) { after.trips[id] = TripSnapshot(trip) } }
            for id in before.placeIDs { if let place = placeRecord(id: id) { after.places[id] = PlaceSnapshot(place) } }
            for id in before.folderIDs { if let folder = folderRecord(id: id) { after.folders[id] = FolderSnapshot(folder) } }
            for key in before.tombstoneKeys { after.tombstones[key] = tombstoneRecord(key)?.deletedAt }
            register(StoreChange(before: before, after: after), action)
        }
        return result
    }

    func touch(_ trip: TripRecord) {
        guard pending?.tripIDs.insert(trip.id).inserted == true else { return }
        pending?.trips[trip.id] = TripSnapshot(trip)
    }

    func touch(_ place: PlaceRecord) {
        guard pending?.placeIDs.insert(place.id).inserted == true else { return }
        pending?.places[place.id] = PlaceSnapshot(place)
    }

    func touch(_ folder: FolderRecord) {
        guard pending?.folderIDs.insert(folder.id).inserted == true else { return }
        pending?.folders[folder.id] = FolderSnapshot(folder)
    }

    func touchNew(trip id: UUID) { pending?.tripIDs.insert(id) }
    func touchNew(place id: UUID) { pending?.placeIDs.insert(id) }
    func touchNew(folder id: UUID) { pending?.folderIDs.insert(id) }

    func touch(tombstone key: TombstoneKey) {
        guard pending?.tombstoneKeys.insert(key).inserted == true else { return }
        if let record = tombstoneRecord(key) { pending?.tombstones[key] = record.deletedAt }
    }

    private func register(_ change: StoreChange, _ action: StoreAction) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { store in
            MainActor.assumeIsolated {
                store.restore(change.before)
                store.didChange()
                store.register(change.reversed, action)
            }
        }
        undoManager.setActionName(actionName(action))
    }

    /// Makes the records in `state` exactly as snapshotted: recreates, updates or deletes them.
    private func restore(_ state: StoreState) {
        // Folders first, so places and trips can link to them.
        for id in state.folderIDs {
            guard let snapshot = state.folders[id] else { continue }
            let record = folderRecord(id: id) ?? {
                let new = FolderRecord(id: id)
                context.insert(new)
                return new
            }()
            snapshot.write(to: record)
        }
        for id in state.placeIDs {
            guard let snapshot = state.places[id] else { continue }
            let record = placeRecord(id: id) ?? {
                let new = PlaceRecord(id: id)
                context.insert(new)
                return new
            }()
            snapshot.write(to: record)
            record.folder = snapshot.value.folderID.flatMap { folderRecord(id: $0) }
        }
        for id in state.tripIDs {
            guard let snapshot = state.trips[id] else {
                if let trip = tripRecord(id: id) { context.delete(trip) }
                continue
            }
            let trip = tripRecord(id: id) ?? {
                let new = TripRecord(id: id)
                context.insert(new)
                return new
            }()
            snapshot.write(to: trip)
            trip.folder = snapshot.folderID.flatMap { folderRecord(id: $0) }
            var existing = Dictionary((trip.stops ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            for stopSnapshot in snapshot.stops {
                let record = existing.removeValue(forKey: stopSnapshot.id) ?? {
                    let new = StopRecord(id: stopSnapshot.id)
                    context.insert(new)
                    return new
                }()
                stopSnapshot.write(to: record)
                record.trip = trip
                record.place = stopSnapshot.placeID.flatMap { placeRecord(id: $0) }
            }
            for leftover in existing.values { deleteStop(leftover) }
        }
        for id in state.placeIDs where state.places[id] == nil {
            if let place = placeRecord(id: id) { context.delete(place) }
        }
        for id in state.folderIDs where state.folders[id] == nil {
            if let folder = folderRecord(id: id) { context.delete(folder) }
        }
        for key in state.tombstoneKeys {
            if let deletedAt = state.tombstones[key] {
                setTombstone(key, deletedAt: deletedAt)
            } else if let record = tombstoneRecord(key) {
                context.delete(record)
            }
        }
    }

    // MARK: - Fetching records

    func tripRecord(id: UUID) -> TripRecord? {
        var descriptor = FetchDescriptor<TripRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    func placeRecord(id: UUID) -> PlaceRecord? {
        var descriptor = FetchDescriptor<PlaceRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    func folderRecord(id: UUID) -> FolderRecord? {
        var descriptor = FetchDescriptor<FolderRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    func allTrips() -> [TripRecord] { (try? context.fetch(FetchDescriptor<TripRecord>())) ?? [] }
    func allFolders() -> [FolderRecord] { (try? context.fetch(FetchDescriptor<FolderRecord>())) ?? [] }
    func allPlaces() -> [PlaceRecord] { (try? context.fetch(FetchDescriptor<PlaceRecord>())) ?? [] }

    func tombstoneRecord(_ key: TombstoneKey) -> DeletionRecord? {
        let raw = key.entityRaw, id = key.entityID
        var descriptor = FetchDescriptor<DeletionRecord>(predicate: #Predicate { $0.entityRaw == raw && $0.entityID == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    // MARK: - Tombstones (call only inside `perform`)

    func setTombstone(_ key: TombstoneKey, deletedAt: Date) {
        if let existing = tombstoneRecord(key) {
            existing.deletedAt = deletedAt
        } else {
            let record = DeletionRecord()
            context.insert(record)
            record.entityRaw = key.entityRaw
            record.entityID = key.entityID
            record.deletedAt = deletedAt
        }
    }

    /// Writes a tombstone for a record this edit deletes.
    func writeTombstone(_ entity: LibraryTombstone.Entity, id: UUID) {
        let key = TombstoneKey(entityRaw: entity.rawValue, entityID: id)
        touch(tombstone: key)
        setTombstone(key, deletedAt: clock())
    }

    // MARK: - Shared ordering helpers

    static func placeOrder(_ a: PlaceRecord, _ b: PlaceRecord) -> Bool {
        if a.sortOrder != b.sortOrder { return a.sortOrder < b.sortOrder }
        switch a.name.localizedStandardCompare(b.name) {
        case .orderedAscending: return true
        case .orderedDescending: return false
        case .orderedSame: return a.id.uuidString < b.id.uuidString
        }
    }

    /// The trips directly in `folder` (nil = unfiled), ordered (sort order, newest edit, id).
    func tripsSorted(in folder: FolderRecord?) -> [TripRecord] {
        allTrips().filter { $0.folder?.id == folder?.id }.sorted {
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    /// New unfiled trips go first: one below the smallest unfiled sort order.
    func firstSortOrder(unfiledTripsExcluding id: UUID) -> Double {
        (tripsSorted(in: nil).filter { $0.id != id }.map(\.sortOrder).min() ?? 1) - 1
    }

    func nextTripSortOrder(in folder: FolderRecord?) -> Double {
        (tripsSorted(in: folder).map(\.sortOrder).max() ?? -1) + 1
    }

    func nextPlaceSortOrder(in folder: FolderRecord) -> Double {
        ((folder.places ?? []).map(\.sortOrder).max() ?? -1) + 1
    }
}
