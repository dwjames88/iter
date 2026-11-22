import Foundation
import IterModel

// Value copies of the records an undoable edit touches. Undo restores these, recreating deleted records with the same
// ids and relationships. They carry every stored column, the V5 ones included.

struct PlaceSnapshot: Sendable {
    /// The whole place, provenance and library metadata included; `folderID` is the folder link.
    var value: Place

    init(_ record: PlaceRecord) { value = record.value() }

    /// Writes the columns; the folder link is set by the store once folders exist.
    func write(to record: PlaceRecord) { record.apply(value) }
}

struct StopSnapshot: Sendable {
    var id: UUID
    var dayIndex: Int
    var sortOrder: Double
    var sessionRaw: String
    var setUpBufferMinutes: Int
    var note: String
    var driveNote: String
    var dwellMinutes: Int
    var fixedArrivalISO: String
    var kindRaw: String
    var placeID: UUID?

    init(_ record: StopRecord) {
        id = record.id
        dayIndex = record.dayIndex
        sortOrder = record.sortOrder
        sessionRaw = record.sessionRaw
        setUpBufferMinutes = record.setUpBufferMinutes
        note = record.note
        driveNote = record.driveNote
        dwellMinutes = record.dwellMinutes
        fixedArrivalISO = record.fixedArrivalISO
        kindRaw = record.kindRaw
        placeID = record.place?.id
    }

    func write(to record: StopRecord) {
        record.dayIndex = dayIndex
        record.sortOrder = sortOrder
        record.sessionRaw = sessionRaw
        record.setUpBufferMinutes = setUpBufferMinutes
        record.note = note
        record.driveNote = driveNote
        record.dwellMinutes = dwellMinutes
        record.fixedArrivalISO = fixedArrivalISO
        record.kindRaw = kindRaw
    }
}

struct TripSnapshot: Sendable {
    var id: UUID
    var name: String
    var startDayISO: String
    var dayCount: Int
    var notes: String
    var createdAt: Date
    var updatedAt: Date
    var folderID: UUID?
    var sortOrder: Double
    var isPinned: Bool
    var pinnedAt: Date?
    var transferTimingsRaw: String
    var startPlaceID: UUID?
    var timeZonePolicyRaw: String
    var stops: [StopSnapshot]

    init(_ record: TripRecord) {
        id = record.id
        name = record.name
        startDayISO = record.startDayISO
        dayCount = record.dayCount
        notes = record.notes
        createdAt = record.createdAt
        updatedAt = record.updatedAt
        folderID = record.folder?.id
        sortOrder = record.sortOrder
        isPinned = record.isPinned
        pinnedAt = record.pinnedAt
        transferTimingsRaw = record.transferTimingsRaw
        startPlaceID = record.startPlaceID
        timeZonePolicyRaw = record.timeZonePolicyRaw
        stops = (record.stops ?? []).map(StopSnapshot.init)
    }

    func write(to record: TripRecord) {
        record.name = name
        record.startDayISO = startDayISO
        record.dayCount = dayCount
        record.notes = notes
        record.createdAt = createdAt
        record.updatedAt = updatedAt
        record.sortOrder = sortOrder
        record.isPinned = isPinned
        record.pinnedAt = pinnedAt
        record.transferTimingsRaw = transferTimingsRaw
        record.startPlaceID = startPlaceID
        record.timeZonePolicyRaw = timeZonePolicyRaw
    }
}

struct FolderSnapshot: Sendable {
    var value: Folder

    init(_ record: FolderRecord) { value = record.value() }

    func write(to record: FolderRecord) { record.apply(value) }
}

/// Which tombstone: an entity kind and the id it deleted.
struct TombstoneKey: Hashable, Sendable {
    var entityRaw: String
    var entityID: UUID
}

/// The state of a set of records at one moment. An id in `tripIDs`, `placeIDs` or `folderIDs` with no snapshot means
/// "does not exist"; the same goes for a tombstone key with no date.
struct StoreState: Sendable {
    var tripIDs: Set<UUID> = []
    var placeIDs: Set<UUID> = []
    var folderIDs: Set<UUID> = []
    var tombstoneKeys: Set<TombstoneKey> = []
    var trips: [UUID: TripSnapshot] = [:]
    var places: [UUID: PlaceSnapshot] = [:]
    var folders: [UUID: FolderSnapshot] = [:]
    var tombstones: [TombstoneKey: Date] = [:]
}

/// One edit: the state of everything it touched before and after.
struct StoreChange: Sendable {
    var before: StoreState
    var after: StoreState
    var reversed: StoreChange { StoreChange(before: after, after: before) }
}
