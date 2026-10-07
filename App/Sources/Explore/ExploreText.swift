import Foundation
import IterCore
import IterFeatures

/// Explore's own phrasing. Light, time and provenance words stay in `LightText` / `TimeText`.
extension LightText {
    // MARK: Intent, sort, filters

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
        case .ask: String(localized: "Ask Iter", comment: "List section: places suggested for a request")
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

    /// True when the row's next event is on a later day than today at the spot.
    static func isTomorrow(_ row: ExploreRow) -> Bool {
        guard let day = row.day else { return false }
        return day != LocalDay.today(in: row.spot.timeZone)
    }

    /// "Sunset, 72, Great, high confidence, 18:42" (plus "tomorrow" for a later day). Loading says "loading light";
    /// a window with no data leaves the score out. nil when there is no window.
    static func rowLight(_ row: ExploreRow) -> String? {
        guard let window = row.window else { return nil }
        var parts = [name(window.kind)]
        if case .scored(let score) = window.assessment {
            parts.append(String(score.value))
            parts.append(name(score.band))
            parts.append(name(score.confidence).lowercased())
        } else if row.isLoading {
            parts.append(String(localized: "loading light", comment: "VoiceOver: the forecast for this row is still loading"))
        }
        if let time = startTime(window, in: row.spot.timeZone) { parts.append(time) }
        if isTomorrow(row) { parts.append(String(localized: "tomorrow", comment: "VoiceOver: the next window is tomorrow")) }
        return parts.joined(separator: ", ")
    }

    static func rowDescription(_ row: ExploreRow, showsDistance: Bool = false) -> String {
        var parts = [row.spot.name, row.spot.locality].filter { !$0.isEmpty }
        if showsDistance, let meters = row.distanceMeters {
            parts.append(String(localized: "\(distance(meters: meters)) away", comment: "VoiceOver: distance from you"))
        }
        if let light = rowLight(row) { parts.append(light) }
        return parts.joined(separator: ", ")
    }
}
