import Foundation
import IterModel
import IterStore

/// A trip as one sidebar or list row: plain values, `Equatable`, so a row that did not change does not redraw.
public struct TripRow: Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var startDay: LocalDay
    public var dayCount: Int
    public var stopCount: Int
    /// The first few place names, in trip order, for a subtitle ("Horseshoe Bend, Monument Valley, ...").
    public var placeNames: [String]
    public var folderID: UUID?
    public var isPinned: Bool
    public var updatedAt: Date

    /// The last day of the trip.
    public var endDay: LocalDay { startDay.adding(days: dayCount - 1) }
}

/// A folder with how many items it holds.
public struct FolderRow: Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var kind: FolderKind
    public var count: Int
    public var isPinned: Bool
}

/// A saved or own place as one row.
public struct PlaceRow: Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var locality: String
    public var category: PlaceCategory
    public var coordinate: Coordinate
    public var origin: PlaceOrigin
    /// The catalogue slug, for curated places.
    public var curatedID: String?
    public var folderID: UUID?
    public var isPinned: Bool
    public var updatedAt: Date
}

/// What an import did, in counts a toast can say ("Added 2 trips, updated 1").
public struct ImportSummary: Equatable, Sendable {
    public var formatVersion: Int
    /// The file's trips were all added as new copies (always for a v1 file, and for "Import as Copy").
    public var asCopy: Bool
    public var tripsAdded: Int
    public var tripsUpdated: Int
    public var tripsRemoved: Int
    public var placesAdded: Int
    public var foldersAdded: Int

    /// Nothing changed (the file was already in the library).
    public var isEmpty: Bool {
        tripsAdded + tripsUpdated + tripsRemoved + placesAdded + foldersAdded == 0
    }
}

/// A library export ready to hand to a save panel or share sheet.
public struct ExportedLibrary: Sendable {
    public var data: Data
    public var suggestedFileName: String
}
