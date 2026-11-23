import Foundation
import SwiftData
import IterModel
@testable import IterStore

/// `expected.json` / `as-written.json` of a fixture: what the OLD code read back from the store.
struct ExpectedStore: Codable {
    struct Folder: Codable {
        var id: UUID, name: String, kindRaw: String, sortOrder: Double, createdAt: Double, updatedAt: Double
        var isPinned: Bool, pinnedAt: Double?, parentID: UUID?, tripIDs: [UUID], placeIDs: [UUID]
    }
    struct Place: Codable {
        var id: UUID, curatedID: String?, originRaw: String, externalID: String?, name: String, locality: String
        var latitude: Double, longitude: Double, timeZoneIdentifier: String, categoryRaw: String, bestLightRaw: String
        var facing: Double?, blurb: String, notes: String, walkInMinutes: Int?, elevationMeters: Double?
        var popularity: Int, tagsRaw: String, isSaved: Bool, createdAt: Double, updatedAt: Double
        var folderID: UUID?, sortOrder: Double, isPinned: Bool, pinnedAt: Double?, stopIDs: [UUID]
    }
    struct Trip: Codable {
        var id: UUID, name: String, startDayISO: String, dayCount: Int, notes: String, createdAt: Double, updatedAt: Double
        var folderID: UUID?, sortOrder: Double, isPinned: Bool, pinnedAt: Double?, transferTimingsRaw: String
        var stopIDs: [UUID]
        var plan: ITERFileV1.TripDTO?
    }
    struct Stop: Codable {
        var id: UUID, dayIndex: Int, sortOrder: Double, sessionRaw: String, setUpBufferMinutes: Int, note: String
        var driveNote: String, tripID: UUID?, placeID: UUID?
    }

    var fixture: String
    var writtenSchemaVersion: String
    var flattenedFolderIDs: [UUID]
    var folders: [Folder]
    var places: [Place]
    var trips: [Trip]
    var stops: [Stop]

    static func load(_ fixture: String, file: String = "expected.json") throws -> ExpectedStore {
        let url = try TestSupport.fixturesRoot.appending(path: "stores/\(fixture)/\(file)")
        return try JSONDecoder().decode(ExpectedStore.self, from: Data(contentsOf: url))
    }

    static let fixtureNames = ["v1", "v2", "v3", "v4-realistic"]

    /// The same shape read from a V5 store by raw fetches (every stored field, not through any repository), for the
    /// dry run's `after.json`. A trip's `plan` is the value the store hands out, converted with the carried v1 encoder.
    static func read(from context: ModelContext, fixture: String, writtenSchemaVersion: String,
                     flattenedFolderIDs: [UUID]) throws -> ExpectedStore {
        func t(_ d: Date) -> Double { d.timeIntervalSinceReferenceDate }
        func sortedByID<T>(_ items: [T], _ id: (T) -> UUID) -> [T] { items.sorted { id($0).uuidString < id($1).uuidString } }
        let folders = try context.fetch(FetchDescriptor<FolderRecord>())
        let places = try context.fetch(FetchDescriptor<PlaceRecord>())
        let trips = try context.fetch(FetchDescriptor<TripRecord>())
        let stops = try context.fetch(FetchDescriptor<StopRecord>())
        func ids<T>(_ items: [T]?, _ id: (T) -> UUID) -> [UUID] { (items ?? []).map(id).sorted { $0.uuidString < $1.uuidString } }
        return ExpectedStore(
            fixture: fixture, writtenSchemaVersion: writtenSchemaVersion, flattenedFolderIDs: flattenedFolderIDs,
            folders: sortedByID(folders, \.id).map {
                Folder(id: $0.id, name: $0.name, kindRaw: $0.kindRaw, sortOrder: $0.sortOrder, createdAt: t($0.createdAt),
                       updatedAt: t($0.updatedAt), isPinned: $0.isPinned, pinnedAt: $0.pinnedAt.map(t), parentID: $0.parent?.id,
                       tripIDs: ids($0.trips, \.id), placeIDs: ids($0.places, \.id))
            },
            places: sortedByID(places, \.id).map {
                Place(id: $0.id, curatedID: $0.curatedID, originRaw: $0.originRaw, externalID: $0.externalID, name: $0.name,
                      locality: $0.locality, latitude: $0.latitude, longitude: $0.longitude,
                      timeZoneIdentifier: $0.timeZoneIdentifier, categoryRaw: $0.categoryRaw, bestLightRaw: $0.bestLightRaw,
                      facing: $0.facing, blurb: $0.blurb, notes: $0.notes, walkInMinutes: $0.walkInMinutes,
                      elevationMeters: $0.elevationMeters, popularity: $0.popularity, tagsRaw: $0.tagsRaw, isSaved: $0.isSaved,
                      createdAt: t($0.createdAt), updatedAt: t($0.updatedAt), folderID: $0.folder?.id, sortOrder: $0.sortOrder,
                      isPinned: $0.isPinned, pinnedAt: $0.pinnedAt.map(t), stopIDs: ids($0.stops, \.id))
            },
            trips: sortedByID(trips, \.id).map {
                Trip(id: $0.id, name: $0.name, startDayISO: $0.startDayISO, dayCount: $0.dayCount, notes: $0.notes,
                     createdAt: t($0.createdAt), updatedAt: t($0.updatedAt), folderID: $0.folder?.id, sortOrder: $0.sortOrder,
                     isPinned: $0.isPinned, pinnedAt: $0.pinnedAt.map(t), transferTimingsRaw: $0.transferTimingsRaw,
                     stopIDs: $0.orderedStops.map(\.id),
                     plan: ITERFileV1(trip: $0.value(), exportedAt: Date(timeIntervalSince1970: 0)).plan)
            },
            stops: sortedByID(stops, \.id).map {
                Stop(id: $0.id, dayIndex: $0.dayIndex, sortOrder: $0.sortOrder, sessionRaw: $0.sessionRaw,
                     setUpBufferMinutes: $0.setUpBufferMinutes, note: $0.note, driveNote: $0.driveNote,
                     tripID: $0.trip?.id, placeID: $0.place?.id)
            })
    }

    /// Reads a dump at any path (the dry run's inputs and outputs).
    static func load(contentsOf url: URL) throws -> ExpectedStore {
        try JSONDecoder().decode(ExpectedStore.self, from: Data(contentsOf: url))
    }
}
