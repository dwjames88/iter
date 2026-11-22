import Foundation
import IterModel

/// What the store holds, as values: the input to the merge planner.
public struct LibrarySnapshot: Sendable {
    public var trips: [Trip]
    public var places: [Place]
    public var folders: [Folder]
    public var tombstones: [LibraryTombstone]

    public init(trips: [Trip] = [], places: [Place] = [], folders: [Folder] = [], tombstones: [LibraryTombstone] = []) {
        self.trips = trips
        self.places = places
        self.folders = folders
        self.tombstones = tombstones
    }
}

/// What to do to one kind of record. Inserts and updates carry the incoming value; deletes are ids.
public struct EntityChanges<Value: Sendable & Hashable>: Sendable, Hashable {
    public var inserts: [Value] = []
    public var updates: [Value] = []
    public var deletes: [UUID] = []

    public init(inserts: [Value] = [], updates: [Value] = [], deletes: [UUID] = []) {
        self.inserts = inserts
        self.updates = updates
        self.deletes = deletes
    }

    public var isEmpty: Bool { inserts.isEmpty && updates.isEmpty && deletes.isEmpty }
}

/// The result of planning an import. Applying it to the store is the repositories' job; this is plain data.
public struct MergePlan: Sendable, Hashable {
    /// A trip and its stops are one unit: an update replaces the whole trip, stops included.
    public var trips = EntityChanges<Trip>()
    public var places = EntityChanges<Place>()
    public var folders = EntityChanges<Folder>()
    /// Incoming tombstones the store should now hold (new, or newer than the one it has).
    public var tombstonesToRecord: [LibraryTombstone] = []
    /// Local tombstones the plan outdates (the incoming record is newer than the deletion).
    public var tombstonesToClear: [LibraryTombstone] = []

    public init() {}

    public var isEmpty: Bool {
        trips.isEmpty && places.isEmpty && folders.isEmpty && tombstonesToRecord.isEmpty && tombstonesToClear.isEmpty
    }

    /// All timestamps are compared at millisecond resolution (the precision of a v2 file), on both sides.
    /// Plans merging `file` into `snapshot` by id:
    /// - an unknown id is inserted;
    /// - for a known id the newer `updatedAt` wins, and a tie keeps the local record (no change);
    /// - an incoming tombstone deletes a local record whose `updatedAt` is older than its `deletedAt`;
    /// - a local tombstone newer than an incoming record's `updatedAt` stops that record being re-inserted;
    /// - a tombstone in the file also suppresses a record in the same file that is older than it.
    public static func plan(merging file: ITERFileV2, into snapshot: LibrarySnapshot) -> MergePlan {
        var plan = MergePlan()
        let incoming = file.tombstones
        let local = snapshot.tombstones
        plan.trips = merge(file.trips, into: snapshot.trips, entity: .trip, incoming: incoming, local: local, plan: &plan)
        plan.places = merge(file.places, into: snapshot.places, entity: .place, incoming: incoming, local: local, plan: &plan)
        plan.folders = merge(file.folders, into: snapshot.folders, entity: .folder, incoming: incoming, local: local, plan: &plan)
        return plan
    }

    /// The explicit "Import as copy" choice: every incoming trip is inserted with a new trip id and new stop ids, and
    /// nothing is updated or deleted. Places and folders merge by id as usual (copies reference the same places), and
    /// incoming tombstones are ignored. `makeID` is injectable for tests.
    public static func asCopy(of file: ITERFileV2, into snapshot: LibrarySnapshot,
                              makeID: () -> UUID = { UUID() }) -> MergePlan {
        var plan = MergePlan()
        var withoutTrips = file
        withoutTrips.tripDTOs = []
        withoutTrips.tombstoneDTOs = []
        let merged = Self.plan(merging: withoutTrips, into: snapshot)
        plan.places = EntityChanges(inserts: merged.places.inserts, updates: merged.places.updates)
        plan.folders = EntityChanges(inserts: merged.folders.inserts, updates: merged.folders.updates)
        plan.trips.inserts = file.trips.map { $0.copyWithNewIDs(makeID: makeID) }
        return plan
    }

    // MARK: Core rule

    private static func merge<R: MergeRecord>(_ records: [R], into localRecords: [R], entity: LibraryTombstone.Entity,
                                              incoming: [LibraryTombstone], local: [LibraryTombstone],
                                              plan: inout MergePlan) -> EntityChanges<R> {
        var changes = EntityChanges<R>()
        let localByID = Dictionary(localRecords.map { ($0.mergeID, $0) }, uniquingKeysWith: { first, _ in first })
        let incomingTombstones = latestTombstones(incoming.filter { $0.entity == entity })
        let localTombstones = latestTombstones(local.filter { $0.entity == entity })
        var seen = Set<UUID>()

        for record in records where seen.insert(record.mergeID).inserted {
            let id = record.mergeID
            if let deleted = incomingTombstones[id], deleted.deletedAt > record.mergeUpdatedAt { continue }
            if let deleted = localTombstones[id] {
                if deleted.deletedAt > record.mergeUpdatedAt { continue }
                plan.tombstonesToClear.append(deleted)
            }
            if let existing = localByID[id] {
                if record.mergeUpdatedAt > existing.mergeUpdatedAt { changes.updates.append(record) }
            } else {
                changes.inserts.append(record)
            }
        }

        // Incoming tombstones, in file order.
        var handled = Set<UUID>()
        for tombstone in incoming where tombstone.entity == entity && handled.insert(tombstone.id).inserted {
            guard let t = incomingTombstones[tombstone.id] else { continue }
            if let existing = localByID[t.id] {
                // An edit at or after the deletion wins and the deletion is not recorded.
                guard existing.mergeUpdatedAt < t.deletedAt else { continue }
                changes.deletes.append(t.id)
            } else if let incomingRecord = records.first(where: { $0.mergeID == t.id }), incomingRecord.mergeUpdatedAt >= t.deletedAt {
                continue
            }
            if let known = localTombstones[t.id], known.deletedAt >= t.deletedAt { continue }
            plan.tombstonesToRecord.append(t)
        }
        return changes
    }

    private static func latestTombstones(_ list: [LibraryTombstone]) -> [UUID: LibraryTombstone] {
        var result: [UUID: LibraryTombstone] = [:]
        for var t in list {
            t.deletedAt = t.deletedAt.millisecondRounded
            if (result[t.id]?.deletedAt ?? .distantPast) <= t.deletedAt { result[t.id] = t }
        }
        return result
    }
}

private protocol MergeRecord: Sendable, Hashable {
    var mergeID: UUID { get }
    var mergeUpdatedAt: Date { get }
}

extension Trip: MergeRecord {
    fileprivate var mergeID: UUID { id }
    fileprivate var mergeUpdatedAt: Date { updatedAt.millisecondRounded }
}

extension Place: MergeRecord {
    fileprivate var mergeID: UUID { id }
    fileprivate var mergeUpdatedAt: Date { updatedAt.millisecondRounded }
}

extension Folder: MergeRecord {
    fileprivate var mergeID: UUID { id }
    fileprivate var mergeUpdatedAt: Date { updatedAt.millisecondRounded }
}

extension Trip {
    /// The same trip under a new trip id and new stop ids. Places, folder and every other field are unchanged.
    public func copyWithNewIDs(makeID: () -> UUID = { UUID() }) -> Trip {
        var copy = self
        copy.id = makeID()
        copy.stops = stops.map { stop in
            var s = stop
            s.id = makeID()
            return s
        }
        return copy
    }
}
