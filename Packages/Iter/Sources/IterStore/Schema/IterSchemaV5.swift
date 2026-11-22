import Foundation
import SwiftData

// The live schema. CloudKit-shaped like V1 to V4: every attribute has a default or is optional, no unique constraints,
// every relationship is optional with an explicit inverse, enums are stored as raw strings.
//
// The four old models keep their EXACT class names (`PlaceRecord`, `TripRecord`, `StopRecord`, `FolderRecord`):
// SwiftData's entity names come from them, and a rename would read as delete and insert. V5 only adds defaulted or
// optional attributes and new models, so V4 to V5 is a lightweight stage.

/// Version 5 of the store: V4 plus place provenance, stop dwell/fixed arrival/kind, the trip's start place and zone
/// policy, and the Go (trip mode), tombstone and sync-peer models.
public enum IterSchemaV5: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(5, 0, 0) }
    public static var models: [any PersistentModel.Type] {
        [PlaceRecord.self, TripRecord.self, StopRecord.self, FolderRecord.self,
         TripRunRecord.self, StopVisitRecord.self, DeletionRecord.self, SyncPeerRecord.self]
    }
}

/// A user folder for trips or locations. Folders are one level deep: nothing nests. `parent` and `children` are
/// deprecated and always nil after `flattenFolders`; they stay because removing them needs a non-lightweight stage.
@Model
public final class FolderRecord {
    public var id: UUID = UUID()
    public var name: String = ""
    public var kindRaw: String = "trips"
    public var sortOrder: Double = 0
    public var createdAt: Date = Date.now
    public var updatedAt: Date = Date.now
    public var isPinned: Bool = false
    public var pinnedAt: Date?
    /// Deprecated: always nil once `flattenFolders` has run.
    public var parent: FolderRecord?

    /// Deprecated, see `parent`: always empty.
    @Relationship(deleteRule: .nullify, inverse: \FolderRecord.parent)
    public var children: [FolderRecord]?
    @Relationship(deleteRule: .nullify, inverse: \TripRecord.folder)
    public var trips: [TripRecord]?
    @Relationship(deleteRule: .nullify, inverse: \PlaceRecord.folder)
    public var places: [PlaceRecord]?

    public init(id: UUID = UUID()) {
        self.id = id
    }
}

@Model
public final class PlaceRecord {
    public var id: UUID = UUID()
    /// The curated slug, for a saved or used curated spot.
    public var curatedID: String?
    public var originRaw: String = "user"
    /// The MapKit (or scout) identifier the place came from.
    public var externalID: String?
    public var name: String = ""
    public var locality: String = ""
    public var latitude: Double = 0
    public var longitude: Double = 0
    public var timeZoneIdentifier: String = "UTC"
    public var categoryRaw: String = "landscape"
    /// `BestLight` raw values joined with commas, in priority order.
    public var bestLightRaw: String = ""
    public var facing: Double?
    public var blurb: String = ""
    public var notes: String = ""
    public var walkInMinutes: Int?
    public var elevationMeters: Double?
    public var popularity: Int = 50
    /// Tags joined with commas.
    public var tagsRaw: String = ""
    public var isSaved: Bool = false
    public var createdAt: Date = Date.now
    public var updatedAt: Date = Date.now
    public var folder: FolderRecord?
    public var sortOrder: Double = 0
    public var isPinned: Bool = false
    public var pinnedAt: Date?

    // V5
    /// `SourceID` raw values joined with commas.
    public var sourcesRaw: String = ""
    /// JSON `[Citation]`.
    public var citationsJSON: String = ""
    /// `confirmed`, `singleSource` or `userPlaced`; empty = not recorded.
    public var verificationRaw: String = ""
    public var discoveredAt: Date?
    /// JSON `HorizonProfile`; empty = none cached.
    public var horizonJSON: String = ""

    @Relationship(deleteRule: .nullify, inverse: \StopRecord.place)
    public var stops: [StopRecord]?

    public init(id: UUID = UUID()) {
        self.id = id
    }
}

@Model
public final class TripRecord {
    public var id: UUID = UUID()
    public var name: String = ""
    /// "YYYY-MM-DD".
    public var startDayISO: String = ""
    public var dayCount: Int = 1
    public var notes: String = ""
    public var createdAt: Date = Date.now
    public var updatedAt: Date = Date.now
    public var folder: FolderRecord?
    public var sortOrder: Double = 0
    public var isPinned: Bool = false
    public var pinnedAt: Date?
    /// Timing of the transfer into each arriving day, as "1:eveningBefore,3:eveningBefore". Morning is not stored.
    public var transferTimingsRaw: String = ""

    // V5
    public var startPlaceID: UUID?
    public var timeZonePolicyRaw: String = "spot"

    @Relationship(deleteRule: .cascade, inverse: \StopRecord.trip)
    public var stops: [StopRecord]?

    public init(id: UUID = UUID()) {
        self.id = id
    }
}

@Model
public final class StopRecord {
    public var id: UUID = UUID()
    public var dayIndex: Int = 0
    public var sortOrder: Double = 0
    public var sessionRaw: String = "goldenEvening"
    public var setUpBufferMinutes: Int = 20
    public var note: String = ""
    public var driveNote: String = ""

    // V5
    /// 0 means "until the window ends".
    public var dwellMinutes: Int = 0
    /// "HH:mm", or empty for none.
    public var fixedArrivalISO: String = ""
    /// `light`, `lodging` or `waypoint`.
    public var kindRaw: String = "light"

    public var trip: TripRecord?
    public var place: PlaceRecord?

    public init(id: UUID = UUID()) {
        self.id = id
    }
}

/// Trip mode: one per run; survives relaunch.
@Model
public final class TripRunRecord {
    public var id: UUID = UUID()
    public var tripID: UUID = UUID()
    /// `armed`, `active`, `paused` or `finished`.
    public var stateRaw: String = "armed"
    public var startedAt: Date?
    public var endedAt: Date?
    public var currentStopID: UUID?
    public var updatedAt: Date = Date.now

    public init(id: UUID = UUID()) {
        self.id = id
    }
}

/// Trip mode: progress through one stop, with the leave and arrival times frozen at departure.
@Model
public final class StopVisitRecord {
    public var id: UUID = UUID()
    public var runID: UUID = UUID()
    public var stopID: UUID = UUID()
    /// `pending`, `enRoute`, `arrived`, `done` or `skipped`.
    public var statusRaw: String = "pending"
    public var departedForAt: Date?
    public var arrivedAt: Date?
    public var leftAt: Date?
    public var plannedLeaveBy: Date?
    public var plannedArrival: Date?
    public var updatedAt: Date = Date.now

    public init(id: UUID = UUID()) {
        self.id = id
    }
}

/// A tombstone for sync merge. Pruned after 90 days.
@Model
public final class DeletionRecord {
    public var id: UUID = UUID()
    public var entityRaw: String = ""
    public var entityID: UUID = UUID()
    public var deletedAt: Date = Date.now

    public init(id: UUID = UUID()) {
        self.id = id
    }
}

/// Bonjour sync state for one paired peer.
@Model
public final class SyncPeerRecord {
    public var id: UUID = UUID()
    public var peerName: String = ""
    public var lastSyncAt: Date?
    public var lastSentToken: String = ""
    /// The Keychain account holding the pairing key.
    public var pairingKeyRef: String = ""

    public init(id: UUID = UUID()) {
        self.id = id
    }
}
