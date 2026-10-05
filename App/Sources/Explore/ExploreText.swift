import Foundation
import IterCore
import IterFeatures

/// Explore's own phrasing. Light, time and provenance words stay in `LightText` / `TimeText`.
extension LightText {
    // MARK: Intent, sort, filters

    static let eachSpotsBest = String(localized: "Each spot's best", comment: "Intent picker: every spot is shown in its own best light")

    static func name(_ sort: ExploreSort) -> String {
        switch sort {
        case .bestLight: String(localized: "Best Light", comment: "Sort option: highest Light Index first")
        case .name: String(localized: "Name", comment: "Sort option")
        case .distance: String(localized: "Distance from Map Centre", comment: "Sort option: nearest to the middle of the map first")
        case .popularity: String(localized: "Popularity", comment: "Sort option: most popular first")
        }
    }

    static func name(_ source: ExploreSource) -> String {
        switch source {
        case .curated: String(localized: "Curated", comment: "Source filter: Iter's hand-picked spots")
        case .yours: String(localized: "Your Spots", comment: "Source filter: spots the user added")
        case .appleMaps: String(localized: "Apple Maps", comment: "Source filter: places found by searching Apple Maps")
        }
    }

    static func name(_ section: ExploreSectionKind) -> String {
        switch section {
        case .spots: String(localized: "Spots", comment: "List section: curated and your own spots")
        case .appleMaps: String(localized: "Apple Maps", comment: "List section: places found by searching Apple Maps")
        }
    }

    // MARK: Time

    /// "6:41 PM" for the start of the window, in the spot's own zone. nil when there is no such window.
    static func startTime(_ window: LightWindow?, in zone: TimeZone) -> String? {
        window.map { TimeText.time($0.span.start, in: zone) }
    }

    /// Shown when the sun never makes the chosen window that day (polar summer or winter).
    static let noWindowToday = String(localized: "No such light today", comment: "Row: the chosen window does not occur on this day at this place")

    // MARK: Search

    static func searchApple(_ query: String) -> String {
        String(localized: "Search Apple Maps for “\(query)”", comment: "List row that runs an Apple Maps search")
    }
    static let searchingApple = String(localized: "Searching Apple Maps…", comment: "Progress while searching")
    static func searchFailed(_ query: String) -> String {
        String(localized: "Couldn't search Apple Maps for “\(query)”.", comment: "Inline error under the search field")
    }
    static func noPlaces(_ query: String) -> String {
        String(localized: "Nothing on Apple Maps matches “\(query)” around the map.", comment: "Shown only after a real search found nothing")
    }

    // MARK: Accessibility

    static func rowDescription(_ row: ExploreRow) -> String {
        var parts = [row.spot.name, row.spot.locality, name(row.spot.origin)].filter { !$0.isEmpty }
        if let window = row.window {
            parts.append(accessibilityDescription(window))
            if let time = startTime(window, in: row.spot.timeZone) {
                parts.append(String(localized: "starts \(time)", comment: "VoiceOver: when the window starts"))
            }
        } else {
            parts.append(noWindowToday)
        }
        return parts.joined(separator: ", ")
    }
}
