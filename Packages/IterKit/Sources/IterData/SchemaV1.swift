import Foundation
import SwiftData
import IterCore

/// Version 1 of the store, frozen: the stored properties and relationships of the three models as they shipped before
/// folders. Never edit these; they exist so SwiftData can read an old store and migrate it to `IterSchemaV2`.
public enum IterSchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    public static var models: [any PersistentModel.Type] { [PlaceRecord.self, TripRecord.self, StopRecord.self] }

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
