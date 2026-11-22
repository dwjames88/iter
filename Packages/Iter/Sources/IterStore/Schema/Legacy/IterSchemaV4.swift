import Foundation
import SwiftData

/// Version 4 of the store, frozen: the stored properties and relationships of the four models as the old app's live
/// `Models.swift` declared them (the shape of the owner's store before the rebuild). Never edit these; they exist so
/// SwiftData can read a V4 store (and migrate it to `IterSchemaV5`), and so the backup can read a store at V4 without
/// touching V5.
///
/// Entity names come from the class names (`PlaceRecord`, `TripRecord`, `StopRecord`, `FolderRecord`), which are the
/// same as the live V5 classes: that is what makes V4 to V5 a lightweight change rather than a delete and insert.
public enum IterSchemaV4: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(4, 0, 0) }
    public static var models: [any PersistentModel.Type] {
        [PlaceRecord.self, TripRecord.self, StopRecord.self, FolderRecord.self]
    }

    @Model
    final class FolderRecord {
        var id: UUID = UUID()
        var name: String = ""
        var kindRaw: String = "trips"
        var sortOrder: Double = 0
        var createdAt: Date = Date.now
        var updatedAt: Date = Date.now
        var isPinned: Bool = false
        var pinnedAt: Date?
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
        var originRaw: String = "user"
        var externalID: String?
        var name: String = ""
        var locality: String = ""
        var latitude: Double = 0
        var longitude: Double = 0
        var timeZoneIdentifier: String = "UTC"
        var categoryRaw: String = "landscape"
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
        var isPinned: Bool = false
        var pinnedAt: Date?

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
        var transferTimingsRaw: String = ""

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
        var sessionRaw: String = "goldenEvening"
        var setUpBufferMinutes: Int = 20
        var note: String = ""
        var driveNote: String = ""

        var trip: TripRecord?
        var place: PlaceRecord?

        init(id: UUID = UUID()) {
            self.id = id
        }
    }
}
