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

    init(_ record: PlaceRecord) {
        id = record.id
        curatedID = record.curatedID
        externalID = record.externalID
        spot = record.spot
        isSaved = record.isSaved
        createdAt = record.createdAt
        updatedAt = record.updatedAt
    }

    func write(to record: PlaceRecord) {
        record.curatedID = curatedID
        record.externalID = externalID
        record.apply(spot)
        record.isSaved = isSaved
        record.createdAt = createdAt
        record.updatedAt = updatedAt
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
    var stops: [StopSnapshot]

    init(_ record: TripRecord) {
        id = record.id
        name = record.name
        startDayISO = record.startDayISO
        dayCount = record.dayCount
        notes = record.notes
        createdAt = record.createdAt
        updatedAt = record.updatedAt
        stops = (record.stops ?? []).map(StopSnapshot.init)
    }

    func write(to record: TripRecord) {
        record.name = name
        record.startDayISO = startDayISO
        record.dayCount = dayCount
        record.notes = notes
        record.createdAt = createdAt
        record.updatedAt = updatedAt
    }
}

/// The state of a set of records at one moment. An ID in `tripIDs` or `placeIDs` with no snapshot means "does not exist".
struct StoreState: Sendable {
    var tripIDs: Set<UUID> = []
    var placeIDs: Set<UUID> = []
    var trips: [UUID: TripSnapshot] = [:]
    var places: [UUID: PlaceSnapshot] = [:]
}

/// One edit: the state of everything it touched before and after.
struct StoreChange: Sendable {
    var before: StoreState
    var after: StoreState
    var reversed: StoreChange { StoreChange(before: after, after: before) }
}
