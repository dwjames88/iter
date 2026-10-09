import Foundation
import SwiftData
import IterCore

/// Version 2 of the store, frozen: the four models as they shipped with folders and per-trip pins, before folders and
/// places could be pinned to the sidebar. Never edit these; they exist so SwiftData can read a V2 store and migrate it
/// to `IterSchemaV3`.
public enum IterSchemaV2: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }
    public static var models: [any PersistentModel.Type] {
        [PlaceRecord.self, TripRecord.self, StopRecord.self, FolderRecord.self]
    }

    @Model
    final class FolderRecord {
        var id: UUID = UUID()
        var name: String = ""
        var kindRaw: String = FolderKind.trips.rawValue
        var sortOrder: Double = 0
        var createdAt: Date = Date.now
        var updatedAt: Date = Date.now
        var parent: FolderRecord?

        @Relationship(deleteRule: .nullify, inverse: \FolderRecord.parent)
        var children: [FolderRecord]?
        @Relationship(deleteRule: .nullify, inverse: \TripRecord.folder)
        var trips: [TripRecord]?
        @Relationship(deleteRule: .nullify, inverse: \PlaceRecord.folder)
        var places: [PlaceRecord]?

        init(id: UUID = UUID()) {
            self.id = id
        }
    }

    @Model
    final class PlaceRecord {
        var id: UUID = UUID()
        var curatedID: String?
        var originRaw: String = SpotOrigin.user.rawValue
        var externalID: String?
        var name: String = ""
        var locality: String = ""
        var latitude: Double = 0
        var longitude: Double = 0
        var timeZoneIdentifier: String = "UTC"
        var categoryRaw: String = SpotCategory.landscape.rawValue
        var bestLightRaw: String = ""
        var facing: Double?
        var blurb: String = ""
        var notes: String = ""
        var walkInMinutes: Int?
        var elevationMeters: Double?
        var popularity: Int = 50
        var tagsRaw: String = ""
        var isSaved: Bool = false
        var createdAt: Date = Date.now
        var updatedAt: Date = Date.now
        var folder: FolderRecord?
        var sortOrder: Double = 0

        @Relationship(deleteRule: .nullify, inverse: \StopRecord.place)
        var stops: [StopRecord]?

        init(id: UUID = UUID()) {
            self.id = id
        }
    }

    @Model
    final class TripRecord {
        var id: UUID = UUID()
        var name: String = ""
        var startDayISO: String = ""
        var dayCount: Int = 1
        var notes: String = ""
        var createdAt: Date = Date.now
        var updatedAt: Date = Date.now
        var folder: FolderRecord?
        var sortOrder: Double = 0
        var isPinned: Bool = false
        var pinnedAt: Date?

        @Relationship(deleteRule: .cascade, inverse: \StopRecord.trip)
        var stops: [StopRecord]?

        init(id: UUID = UUID()) {
            self.id = id
        }
    }

    @Model
    final class StopRecord {
        var id: UUID = UUID()
        var dayIndex: Int = 0
        var sortOrder: Double = 0
        var sessionRaw: String = LightWindowKind.goldenEvening.rawValue
        var setUpBufferMinutes: Int = 20
        var note: String = ""

        var trip: TripRecord?
        var place: PlaceRecord?

        init(id: UUID = UUID()) {
            self.id = id
        }
    }
}
