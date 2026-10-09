import Foundation
import IterCore

// Value copies of the records an undoable edit touches. Undo restores these, recreating deleted
// records with the same IDs and relationships.

struct PlaceSnapshot: Sendable {
    var id: UUID
    var curatedID: String?
    var externalID: String?
    var spot: Spot
    var isSaved: Bool
    var createdAt: Date
    var updatedAt: Date
    var folderID: UUID?
    var sortOrder: Double
    var isPinned: Bool
    var pinnedAt: Date?

    init(_ record: PlaceRecord) {
        id = record.id
        curatedID = record.curatedID
        externalID = record.externalID
        spot = record.spot
        isSaved = record.isSaved
        createdAt = record.createdAt
        updatedAt = record.updatedAt
        folderID = record.folder?.id
        sortOrder = record.sortOrder
        isPinned = record.isPinned
        pinnedAt = record.pinnedAt
    }

    /// Writes the fields; the folder link is set by the store (`folderID`), once folders exist.
    func write(to record: PlaceRecord) {
        record.curatedID = curatedID
        record.externalID = externalID
        record.apply(spot)
        record.isSaved = isSaved
        record.createdAt = createdAt
        record.updatedAt = updatedAt
        record.sortOrder = sortOrder
        record.isPinned = isPinned
        record.pinnedAt = pinnedAt
    }
}

struct StopSnapshot: Sendable {
    var id: UUID
    var dayIndex: Int
    var sortOrder: Double
    var sessionRaw: String
    var setUpBufferMinutes: Int
    var note: String
    var placeID: UUID?

    init(_ record: StopRecord) {
        id = record.id
        dayIndex = record.dayIndex
        sortOrder = record.sortOrder
        sessionRaw = record.sessionRaw
        setUpBufferMinutes = record.setUpBufferMinutes
        note = record.note
        placeID = record.place?.id
    }

    func write(to record: StopRecord) {
        record.dayIndex = dayIndex
        record.sortOrder = sortOrder
        record.sessionRaw = sessionRaw
        record.setUpBufferMinutes = setUpBufferMinutes
        record.note = note
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
    }
}

struct FolderSnapshot: Sendable {
    var id: UUID
    var name: String
    var kindRaw: String
    var sortOrder: Double
    var createdAt: Date
    var updatedAt: Date
    var isPinned: Bool
    var pinnedAt: Date?

    init(_ record: FolderRecord) {
        id = record.id
        name = record.name
        kindRaw = record.kindRaw
        sortOrder = record.sortOrder
        createdAt = record.createdAt
        updatedAt = record.updatedAt
        isPinned = record.isPinned
        pinnedAt = record.pinnedAt
    }

    /// Writes the fields.
    func write(to record: FolderRecord) {
        record.name = name
        record.kindRaw = kindRaw
        record.sortOrder = sortOrder
        record.createdAt = createdAt
        record.updatedAt = updatedAt
        record.isPinned = isPinned
        record.pinnedAt = pinnedAt
    }
}

/// The state of a set of records at one moment. An ID in `tripIDs`, `placeIDs` or `folderIDs` with no snapshot means "does not exist".
struct StoreState: Sendable {
    var tripIDs: Set<UUID> = []
    var placeIDs: Set<UUID> = []
    var folderIDs: Set<UUID> = []
    var trips: [UUID: TripSnapshot] = [:]
    var places: [UUID: PlaceSnapshot] = [:]
    var folders: [UUID: FolderSnapshot] = [:]
}

/// One edit: the state of everything it touched before and after.
struct StoreChange: Sendable {
    var before: StoreState
    var after: StoreState
    var reversed: StoreChange { StoreChange(before: after, after: before) }
}
