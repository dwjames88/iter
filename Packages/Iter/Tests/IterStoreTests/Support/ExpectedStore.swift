import Foundation
@testable import IterStore

/// `expected.json` / `as-written.json` of a fixture: what the OLD code read back from the store.
struct ExpectedStore: Decodable {
    struct Folder: Decodable {
        var id: UUID, name: String, kindRaw: String, sortOrder: Double, createdAt: Double, updatedAt: Double
        var isPinned: Bool, pinnedAt: Double?, parentID: UUID?, tripIDs: [UUID], placeIDs: [UUID]
    }
    struct Place: Decodable {
        var id: UUID, curatedID: String?, originRaw: String, externalID: String?, name: String, locality: String
        var latitude: Double, longitude: Double, timeZoneIdentifier: String, categoryRaw: String, bestLightRaw: String
        var facing: Double?, blurb: String, notes: String, walkInMinutes: Int?, elevationMeters: Double?
        var popularity: Int, tagsRaw: String, isSaved: Bool, createdAt: Double, updatedAt: Double
        var folderID: UUID?, sortOrder: Double, isPinned: Bool, pinnedAt: Double?, stopIDs: [UUID]
    }
    struct Trip: Decodable {
        var id: UUID, name: String, startDayISO: String, dayCount: Int, notes: String, createdAt: Double, updatedAt: Double
        var folderID: UUID?, sortOrder: Double, isPinned: Bool, pinnedAt: Double?, transferTimingsRaw: String
        var stopIDs: [UUID]
        var plan: ITERFileV1.TripDTO?
    }
    struct Stop: Decodable {
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
}
