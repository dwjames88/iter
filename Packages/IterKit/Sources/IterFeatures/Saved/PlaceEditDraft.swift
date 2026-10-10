import Foundation
import IterCore
import IterData

/// The form state of the place editor: edits a saved or own place. Platform-neutral so it can be tested.
/// Cancel drops the draft; Done turns it into one `PlaceEdit`.
public struct PlaceEditDraft: Equatable, Sendable {
    public var name: String
    public var locality: String
    public var notes: String
    public var category: SpotCategory
    public var bestLight: Set<BestLight>
    /// Tags as typed, separated by commas.
    public var tagsText: String
    public var walkInText: String
    /// Edited by `CoordinateFieldsSection`, which only writes a valid coordinate here.
    public var coordinate: Coordinate
    public var timeZoneIdentifier: String
    public var folderID: UUID?
    public var isPinned: Bool
    public let origin: SpotOrigin
    private let startCoordinate: Coordinate

    public init(_ record: PlaceRecord) {
        name = record.name
        locality = record.locality
        notes = record.notes
        category = record.category
        bestLight = Set(record.bestLight)
        tagsText = record.tags.joined(separator: ", ")
        walkInText = record.walkInMinutes.map(String.init) ?? ""
        coordinate = record.coordinate
        timeZoneIdentifier = record.timeZoneIdentifier
        folderID = record.folder?.id
        isPinned = record.isPinned
        origin = record.origin
        startCoordinate = record.coordinate
    }

    /// Whether category, best light, walk-in, tags and the coordinate can be changed. False for a curated spot.
    public var editsFacts: Bool { PlaceEdit.editsFacts(of: origin) }

    public enum Problem: Hashable, Sendable {
        case nameRequired, walkInInvalid
    }

    public var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The coordinate differs from where the place was.
    public var movesPlace: Bool { editsFacts && coordinate != startCoordinate }

    public var walkInMinutes: Int?? {
        let trimmed = walkInText.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return .some(nil) }
        guard let n = Int(trimmed), (0...SpotDraft.maximumWalkInMinutes).contains(n) else { return nil }
        return .some(n)
    }

    public var problems: Set<Problem> {
        var out = Set<Problem>()
        if trimmedName.isEmpty { out.insert(.nameRequired) }
        guard editsFacts else { return out }
        if walkInMinutes == nil { out.insert(.walkInInvalid) }
        return out
    }

    public var isValid: Bool { problems.isEmpty }

    /// The tags typed, trimmed, without empties or repeats.
    public var tags: [String] {
        var seen = Set<String>()
        return tagsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    /// Takes a reverse-geocode answer's time zone after the coordinate moved. Never touches typed text.
    public mutating func applyTimeZone(from lookup: PlaceResult) {
        if let zone = lookup.timeZoneIdentifier, TimeZone(identifier: zone) != nil { timeZoneIdentifier = zone }
    }

    /// The edit to apply, or nil while the draft has problems. A curated spot keeps its catalogue facts.
    public func edit(for record: PlaceRecord) -> PlaceEdit? {
        guard isValid else { return nil }
        var edit = PlaceEdit(record)
        edit.name = trimmedName
        edit.locality = locality.trimmingCharacters(in: .whitespacesAndNewlines)
        edit.notes = notes
        edit.folderID = folderID
        edit.isPinned = isPinned
        if editsFacts, let walkIn = walkInMinutes {
            edit.category = category
            edit.bestLight = BestLight.allCases.filter(bestLight.contains)
            edit.tags = tags
            edit.walkInMinutes = walkIn
            if coordinate != startCoordinate {
                edit.coordinate = coordinate
                edit.timeZoneIdentifier = timeZoneIdentifier == record.timeZoneIdentifier
                    ? TimeZoneEstimate.identifier(for: coordinate) : timeZoneIdentifier
            }
        }
        return edit
    }
}
