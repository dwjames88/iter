import Foundation
import IterCore
import IterData

/// The form state of the spot editor, with validation. Platform-neutral so it can be tested.
public struct SpotDraft: Equatable, Sendable {
    public var name = ""
    public var locality = ""
    public var notes = ""
    public var coordinate: Coordinate
    public var timeZoneIdentifier: String
    public var category: SpotCategory = .landscape
    public var bestLight: Set<BestLight> = []
    /// What the user typed; empty means unknown.
    public var walkInText = ""
    /// True when the zone is this Mac's because the lookup failed or has not answered.
    public var timeZoneIsFallback: Bool

    /// Without a zone the estimate for the coordinate is used (never the Mac's), and it stays marked as a fallback.
    public init(coordinate: Coordinate, timeZone: TimeZone? = nil, timeZoneIsFallback: Bool = true) {
        self.coordinate = coordinate
        self.timeZoneIdentifier = timeZone?.identifier ?? TimeZoneEstimate.identifier(for: coordinate)
        self.timeZoneIsFallback = timeZoneIsFallback
    }

    public enum Problem: Hashable, Sendable {
        case nameRequired
        case walkInInvalid
    }

    public static let maximumWalkInMinutes = 600

    /// nil when empty, the minutes when valid. `.some(nil)` is "unknown".
    public var walkInMinutes: Int?? {
        let trimmed = walkInText.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return .some(nil) }
        guard let n = Int(trimmed), (0...Self.maximumWalkInMinutes).contains(n) else { return nil }
        return .some(n)
    }

    public var problems: Set<Problem> {
        var out = Set<Problem>()
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { out.insert(.nameRequired) }
        if walkInMinutes == nil { out.insert(.walkInInvalid) }
        return out
    }

    public var isValid: Bool { problems.isEmpty }

    public var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    public var trimmedLocality: String { locality.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Best light in the canonical order, so saving twice gives the same record.
    public var orderedBestLight: [BestLight] { BestLight.allCases.filter(bestLight.contains) }

    /// Applies a reverse-geocode answer: fills only what the user has not typed, and takes the zone when there is one.
    public mutating func apply(lookup: PlaceResult, fillName: Bool, fillLocality: Bool) {
        if fillName, !lookup.name.isEmpty { name = lookup.name }
        if fillLocality, !lookup.locality.isEmpty { locality = lookup.locality }
        if let zone = lookup.timeZoneIdentifier, TimeZone(identifier: zone) != nil {
            timeZoneIdentifier = zone
            timeZoneIsFallback = false
        }
    }
}
