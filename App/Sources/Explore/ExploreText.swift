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
        case .distance: String(localized: "Distance", comment: "Sort option: nearest first; from your location, or from the middle of the map when there is no location")
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
        case .nearYou: String(localized: "Near You", comment: "List section: spots close to your location")
        case .popular: String(localized: "Popular", comment: "List section: iconic spots beyond the near-you radius")
        case .morePlaces: String(localized: "More Places", comment: "List section: every other spot beyond the near-you radius")
        case .appleMaps: String(localized: "Apple Maps", comment: "List section: places found by searching Apple Maps")
        }
    }

    // MARK: Near you

    /// "Near You · Within 300 mi". The radius is a setting in miles.
    static func nearYouTitle(radiusMiles: Int) -> String {
        let radius = Measurement(value: Double(radiusMiles), unit: UnitLength.miles)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0))))
        return String(localized: "Near You · Within \(radius)", comment: "List section title: the distance is the near-you radius, e.g. 300 mi")
    }

    /// "42 mi" in the user's units for a road distance.
    static func distance(meters: Double) -> String {
        Measurement(value: meters, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road, numberFormatStyle: .number.precision(.fractionLength(0))))
    }

    static func radiusChoice(_ miles: Int) -> String {
        Measurement(value: Double(miles), unit: UnitLength.miles)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0))))
    }

    static let locationPromptTitle = String(localized: "Show spots near you", comment: "Explore banner title when location is not yet allowed")
    static func locationPromptDetail(radiusMiles: Int) -> String {
        String(localized: "Iter uses your location to show spots within \(radiusMiles) miles.", comment: "Explore banner: why location is asked for; the number is the radius in miles")
    }
    static let useMyLocation = String(localized: "Use My Location", comment: "Button: allow location for the near-you list")
    static let openLocationSettings = String(localized: "Open Location Settings", comment: "Button: open System Settings > Location Services")
    static let findingLocation = String(localized: "Finding your location…", comment: "Progress in the Explore banner while the location is being found")
    static let locationUnavailable = String(localized: "Couldn't find your location.", comment: "Explore banner: no fix yet")
    static let tryAgain = String(localized: "Try Again", comment: "Button: look for the location again")
    static let nearYouRadius = String(localized: "Near You Radius", comment: "Menu section title: how far Near You reaches")

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

    static func rowDescription(_ row: ExploreRow, showsDistance: Bool = false) -> String {
        var parts = [row.spot.name, row.spot.locality, name(row.spot.origin)].filter { !$0.isEmpty }
        if showsDistance, let meters = row.distanceMeters {
            parts.append(String(localized: "\(distance(meters: meters)) away", comment: "VoiceOver: distance from you"))
        }
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
