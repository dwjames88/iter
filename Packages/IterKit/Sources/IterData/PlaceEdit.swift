import Foundation
import IterCore

/// Everything the place editor can change about a saved or own place, as one value.
///
/// Which fields count depends on where the place came from (`PlaceEdit.editsFacts`): a curated spot's coordinate,
/// category, best light, walk-in and tags are the catalogue's facts, so `IterStore.editPlace` leaves them alone and the
/// editor shows them read-only. Name, place, notes, folder and pin are yours on every saved place.
public struct PlaceEdit: Sendable, Equatable {
    public var name: String
    public var locality: String
    public var notes: String
    public var category: SpotCategory
    public var bestLight: [BestLight]
    public var tags: [String]
    public var walkInMinutes: Int?
    public var coordinate: Coordinate
    public var timeZoneIdentifier: String
    /// The location folder the place is filed in; nil = unfiled.
    public var folderID: UUID?
    public var isPinned: Bool

    /// The place as it is now.
    public init(_ record: PlaceRecord) {
        name = record.name
        locality = record.locality
        notes = record.notes
        category = record.category
        bestLight = record.bestLight
        tags = record.tags
        walkInMinutes = record.walkInMinutes
        coordinate = record.coordinate
        timeZoneIdentifier = record.timeZoneIdentifier
        folderID = record.folder?.id
        isPinned = record.isPinned
    }

    /// Whether the place's own facts (coordinate, category, best light, walk-in, tags) are the user's to change.
    /// False for a curated spot: those come from Iter's catalogue.
    public static func editsFacts(of origin: SpotOrigin) -> Bool { origin != .curated }
}
