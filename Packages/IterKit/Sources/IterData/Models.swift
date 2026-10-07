import Foundation
import SwiftData
import IterCore

// CloudKit-compatible: every attribute has a default or is optional, no unique constraints,
// every relationship is optional with an explicit inverse, enums are stored as raw strings.

/// What a folder holds. A folder never mixes kinds, and a subfolder has its parent's kind.
public enum FolderKind: String, Sendable, CaseIterable {
    case trips, locations
}

/// A user folder for trips or locations. Nests at most one level (a parent is always a root folder of the same kind).
/// Deleting a folder never deletes what is in it; `IterStore.deleteFolder` moves the contents up.
@Model
public final class FolderRecord {
    public var id: UUID = UUID()
    public var name: String = ""
    public var kindRaw: String = FolderKind.trips.rawValue
    public var sortOrder: Double = 0
    public var createdAt: Date = Date.now
    public var updatedAt: Date = Date.now
    public var parent: FolderRecord?

    @Relationship(deleteRule: .nullify, inverse: \FolderRecord.parent)
    public var children: [FolderRecord]?
    @Relationship(deleteRule: .nullify, inverse: \TripRecord.folder)
    public var trips: [TripRecord]?
    @Relationship(deleteRule: .nullify, inverse: \PlaceRecord.folder)
    public var places: [PlaceRecord]?

    public init(id: UUID = UUID()) {
        self.id = id
    }

    public var kind: FolderKind {
        get { FolderKind(rawValue: kindRaw) ?? .trips }
        set { kindRaw = newValue.rawValue }
    }
}

@Model
public final class PlaceRecord {
    public var id: UUID = UUID()
    /// The curated slug, for a saved or used curated spot.
    public var curatedID: String?
    public var originRaw: String = SpotOrigin.user.rawValue
    /// The MapKit (or scout) identifier the place came from.
    public var externalID: String?
    public var name: String = ""
    public var locality: String = ""
    public var latitude: Double = 0
    public var longitude: Double = 0
    public var timeZoneIdentifier: String = "UTC"
    public var categoryRaw: String = SpotCategory.landscape.rawValue
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
    /// The location folder this place is filed in; nil = unfiled.
    public var folder: FolderRecord?
    /// Order within its folder (ascending).
    public var sortOrder: Double = 0

    @Relationship(deleteRule: .nullify, inverse: \StopRecord.place)
    public var stops: [StopRecord]?

    public init(id: UUID = UUID()) {
        self.id = id
    }

    public var origin: SpotOrigin {
        get { SpotOrigin(rawValue: originRaw) ?? .user }
        set { originRaw = newValue.rawValue }
    }

    public var category: SpotCategory {
        get { SpotCategory(rawValue: categoryRaw) ?? .landscape }
        set { categoryRaw = newValue.rawValue }
    }

    public var bestLight: [BestLight] {
        get { bestLightRaw.split(separator: ",").compactMap { BestLight(rawValue: String($0)) } }
        set { bestLightRaw = newValue.map(\.rawValue).joined(separator: ",") }
    }

    public var tags: [String] {
        get { tagsRaw.split(separator: ",").map(String.init) }
        set { tagsRaw = newValue.joined(separator: ",") }
    }

    public var coordinate: Coordinate {
        get { Coordinate(latitude: latitude, longitude: longitude) }
        set { latitude = newValue.latitude; longitude = newValue.longitude }
    }

    /// The value form. Curated records keep the curated slug as `Spot.id`; everything else uses the UUID string.
    public var spot: Spot {
        Spot(id: curatedID ?? id.uuidString, name: name, locality: locality, coordinate: coordinate,
             timeZoneIdentifier: timeZoneIdentifier, category: category, bestLight: bestLight, facing: facing,
             blurb: blurb, notes: notes, walkInMinutes: walkInMinutes, elevationMeters: elevationMeters,
             popularity: popularity, tags: tags, origin: origin)
    }

    /// Copies a spot's content (not identity) into this record.
    func apply(_ spot: Spot) {
        name = spot.name
        locality = spot.locality
        coordinate = spot.coordinate
        timeZoneIdentifier = spot.timeZoneIdentifier
        category = spot.category
        bestLight = spot.bestLight
        facing = spot.facing
        blurb = spot.blurb
        notes = spot.notes
        walkInMinutes = spot.walkInMinutes
        elevationMeters = spot.elevationMeters
        popularity = spot.popularity
        tags = spot.tags
        origin = spot.origin
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
    /// The trip folder this trip is filed in; nil = unfiled.
    public var folder: FolderRecord?
    /// Order within its folder, or among unfiled trips (ascending).
    public var sortOrder: Double = 0
    public var isPinned: Bool = false
    /// When the trip was pinned; orders the pinned group.
    public var pinnedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \StopRecord.trip)
    public var stops: [StopRecord]?

    public init(id: UUID = UUID()) {
        self.id = id
    }

    public var startDay: LocalDay {
        get { LocalDay(iso: startDayISO) ?? LocalDay(year: 1970, month: 1, day: 1) }
        set { startDayISO = newValue.iso }
    }

    /// Stops ordered by day, then by `sortOrder`.
    public var orderedStops: [StopRecord] {
        (stops ?? []).sorted {
            ($0.dayIndex, $0.sortOrder, $0.id.uuidString) < ($1.dayIndex, $1.sortOrder, $1.id.uuidString)
        }
    }

    public func orderedStops(onDay day: Int) -> [StopRecord] {
        orderedStops.filter { $0.dayIndex == day }
    }

    public var plan: TripPlan {
        TripPlan(id: id, name: name, startDay: startDay, dayCount: dayCount,
                 stops: orderedStops.compactMap(\.plan), notes: notes)
    }
}

@Model
public final class StopRecord {
    public var id: UUID = UUID()
    public var dayIndex: Int = 0
    public var sortOrder: Double = 0
    public var sessionRaw: String = LightWindowKind.goldenEvening.rawValue
    public var setUpBufferMinutes: Int = 20
    public var note: String = ""

    public var trip: TripRecord?
    public var place: PlaceRecord?

    public init(id: UUID = UUID()) {
        self.id = id
    }

    public var session: LightWindowKind {
        get { LightWindowKind(rawValue: sessionRaw) ?? .goldenEvening }
        set { sessionRaw = newValue.rawValue }
    }

    /// nil only if the place is missing (a broken link); such a stop is left out of the plan.
    public var plan: TripStopPlan? {
        guard let place else { return nil }
        return TripStopPlan(id: id, spot: place.spot, dayIndex: dayIndex, session: session,
                            setUpBufferMinutes: setUpBufferMinutes, note: note)
    }
}
