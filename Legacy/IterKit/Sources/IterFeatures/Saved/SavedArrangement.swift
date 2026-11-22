import Foundation
import IterCore

public enum SavedSort: String, CaseIterable, Hashable, Sendable {
    case name
    case lightToday
    case kind
}

public enum SavedFilter: String, CaseIterable, Hashable, Sendable {
    case all
    case addedByYou
    case curated
    case appleMaps
}

/// One row of Saved: a saved curated or Apple Maps spot, or one of the user's own.
public struct SavedItem: Identifiable, Hashable, Sendable {
    /// The `PlaceRecord` id.
    public let id: UUID
    public let spot: Spot
    /// Today's headline score for the row's intent, nil when there is no forecast.
    public let todayScore: Int?

    public init(id: UUID, spot: Spot, todayScore: Int?) {
        self.id = id
        self.spot = spot
        self.todayScore = todayScore
    }
}

public enum SavedArranger {
    public static func arrange(_ items: [SavedItem], query: String, filter: SavedFilter, sort: SavedSort) -> [SavedItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let kept = items.filter { item in
            switch filter {
            case .all: break
            case .addedByYou: guard item.spot.origin == .user else { return false }
            case .curated: guard item.spot.origin == .curated else { return false }
            case .appleMaps: guard item.spot.origin == .appleMaps || item.spot.origin == .scout else { return false }
            }
            guard !trimmed.isEmpty else { return true }
            return item.spot.name.localizedStandardContains(trimmed) || item.spot.locality.localizedStandardContains(trimmed)
        }
        let byName: (SavedItem, SavedItem) -> Bool = {
            $0.spot.name.localizedStandardCompare($1.spot.name) == .orderedAscending
        }
        switch sort {
        case .name:
            return kept.sorted(by: byName)
        case .lightToday:
            return kept.sorted { a, b in
                switch (a.todayScore, b.todayScore) {
                case let (x?, y?) where x != y: return x > y
                case (.some, nil): return true
                case (nil, .some): return false
                default: return byName(a, b)
                }
            }
        case .kind:
            let order = Dictionary(uniqueKeysWithValues: SpotCategory.allCases.enumerated().map { ($1, $0) })
            return kept.sorted { a, b in
                let x = order[a.spot.category] ?? 0, y = order[b.spot.category] ?? 0
                return x != y ? x < y : byName(a, b)
            }
        }
    }
}
