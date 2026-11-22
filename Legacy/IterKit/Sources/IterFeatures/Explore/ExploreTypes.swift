import Foundation
import IterCore

/// Where an Explore result comes from. Drives the Source filter.
public enum ExploreSource: String, CaseIterable, Hashable, Sendable, Identifiable {
    case curated
    case yours
    case appleMaps

    public var id: String { rawValue }
}

public enum ExploreSort: String, CaseIterable, Hashable, Sendable, Identifiable {
    /// Highest Light Index first; spots with no forecast come last.
    case bestLight
    case name
    /// Nearest first: to you when there is a location, else to the centre of the visible map.
    case distance
    /// Most popular (iconic, crowded) first.
    case popularity

    public var id: String { rawValue }
}

/// The Explore filters. Empty `categories` and `bestLight` mean "any".
public struct ExploreFilters: Equatable, Sendable {
    public var categories: Set<SpotCategory> = []
    /// What a spot is known for. Apple Maps results have no "best at" and are not filtered by it.
    public var bestLight: Set<BestLight> = []
    public var sources: Set<ExploreSource> = Set(ExploreSource.allCases)

    public init(categories: Set<SpotCategory> = [], bestLight: Set<BestLight> = [],
                sources: Set<ExploreSource> = Set(ExploreSource.allCases)) {
        self.categories = categories
        self.bestLight = bestLight
        self.sources = sources
    }

    /// How many filter groups are narrowing the list (the toolbar badge).
    public var activeCount: Int {
        (categories.isEmpty ? 0 : 1) + (bestLight.isEmpty ? 0 : 1) + (sources.count == ExploreSource.allCases.count ? 0 : 1)
    }

    public var isActive: Bool { activeCount > 0 }

    public static let none = ExploreFilters()
}

/// One row of the Explore list (and one pin on the map).
public struct ExploreRow: Identifiable, Hashable, Sendable {
    public var spot: Spot
    public var source: ExploreSource
    /// The spot's next event (sunrise or sunset) by its own clock; unscored while there is no forecast.
    public var window: LightWindow?
    /// The local day of that event.
    public var day: LocalDay?
    /// The forecast is in flight and nothing is cached yet.
    public var isLoading: Bool = false
    /// Straight-line metres from you when there is a location; else from the centre of the visible map while sorting
    /// by distance; else nil.
    public var distanceMeters: Double?
    /// The scout's one-sentence reason, on rows of the Ask section only.
    public var note: String?
    /// Drive time the scout computed, on rows of the Ask section only.
    public var driveSeconds: TimeInterval?
    /// Ask found this place (In View rows only), so the app can draw it as an Ask result.
    public var viaAsk: Bool = false
    /// Every data source that lists the place (Apple Maps, OpenStreetMap, Wikipedia, ...); empty for curated and
    /// your own spots. `viaAsk` is the Ask marker beside it.
    public var sources: Set<DiscoverySourceID> = []
    /// Height above sea level in metres, when a source gave one.
    public var elevationMeters: Double?
    /// Pages that mention the place.
    public var links: [URL] = []

    public var id: String { spot.id }
    public var score: Int? { window?.score }

    /// Why there is no score, when there is none and the reason is specific.
    public var unavailableReason: ForecastUnavailableReason? {
        if case .noForecast(let reason)? = window?.assessment { return reason }
        return nil
    }
}

public enum ExploreSectionKind: Hashable, Sendable {
    /// What Search Here found in the visible map region. First when present.
    case inView
    /// What a typed "<feature> in <area>" search found: Discovery and Apple Maps together, inside the area. After the
    /// Ask section when there is one, otherwise first.
    case feature
    /// What the ask engine suggested for the request. Always first; rows come only from its grounded suggestions.
    case ask
    /// Curated and your own spots, when there is no location to group them by.
    case spots
    /// Curated and your own spots within the radius of you.
    case nearYou
    /// Iconic curated spots beyond the radius (popularity at or above `ExploreModel.popularThreshold`).
    case popular
    /// Every other spot beyond the radius. Collapsed by default.
    case morePlaces
    case appleMaps
}

public struct ExploreSection: Identifiable, Hashable, Sendable {
    public var kind: ExploreSectionKind
    public var rows: [ExploreRow]
    public var id: ExploreSectionKind { kind }
}

/// Apple Maps search progress. Messages are phrased by the app.
public enum ExploreSearchState: Equatable, Sendable {
    case idle
    case searching(query: String)
    case finished(query: String, count: Int)
    case failed(query: String)

    public var isSearching: Bool {
        if case .searching = self { return true }
        return false
    }
}

/// Progress and outcome of a typed "<feature> in <area>" search, as facts. The app phrases them.
public struct FeatureSearchStatus: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case idle
        /// Looking up the area and its outline.
        case resolvingArea
        /// Apple Maps and Discovery are searching; results show as each finishes.
        case searching
        case finished
    }

    public var phase: Phase = .idle
    /// The text that was searched.
    public var query = ""
    public var feature: FeatureKind?
    /// The area as typed.
    public var areaName = ""
    /// The area could not be found, so the search fell back to a plain Apple Maps search.
    public var areaNotFound = false
    /// The area's real outline was found (results are cut to it); otherwise a box around it was used.
    public var hasBoundary = false
    public var maps: SearchHereStatus.MapsOutcome = .pending
    /// What happened to each Discovery source (`.unavailable(reason)`, `.needsKey`, ...). Empty until Discovery ends.
    public var sources: [DiscoverySourceID: DiscoverySourceStatus] = [:]
    /// Discovery itself failed (not a single source).
    public var discoveryFailed = false
    /// Results listed now.
    public var total = 0

    public init() {}

    public static let idle = FeatureSearchStatus()

    public var isSearching: Bool { phase == .resolvingArea || phase == .searching }
}

/// How a pin is drawn. The map has hierarchy (critique C28): one selected, a few chips, the rest dots.
public enum ExplorePinStyle: Equatable, Sendable {
    case selected
    case chip
    case dot
}

/// What a pin draws of its spot's next window, and nothing more: cheap to compare, so an unrelated forecast arriving
/// leaves every other pin equal and MapKit does not touch its annotation.
public struct ExplorePinLight: Equatable, Sendable {
    public struct Score: Equatable, Sendable {
        public var value: Int
        public var band: LightBand
        public var confidence: Confidence
    }
    public var kind: LightWindowKind
    /// nil while there is no forecast.
    public var score: Score?
    public var start: Date
    /// The forecast is in flight (VoiceOver says "loading light").
    public var isLoading: Bool
    /// The window falls on a later day than today at the spot.
    public var isTomorrow: Bool
}

public struct ExplorePin: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var locality: String
    public var coordinate: Coordinate
    public var timeZoneIdentifier: String
    public var style: ExplorePinStyle
    public var light: ExplorePinLight?

    public var timeZone: TimeZone { TimeZone(identifier: timeZoneIdentifier) ?? .gmt }
    public var band: LightBand? { light?.score?.band }
    public var scoreValue: Int? { light?.score?.value }
}

/// Several pins that would overlap at this zoom, drawn as one count. The id comes from the grid cell, so it is the same
/// while the map pans and while the same pins stay in the cell.
public struct ExploreCluster: Identifiable, Equatable, Sendable {
    public var id: String
    /// The mean of the members' coordinates.
    public var coordinate: Coordinate
    public var count: Int
    /// The best member's score and band (nil when no member is scored).
    public var bestScore: Int?
    public var bestBand: LightBand?
    /// Member ids in id order.
    public var memberIDs: [String]
    /// The members' coordinates in member order, for the zoom-to-fit.
    public var memberCoordinates: [Coordinate]
}

/// One annotation on the map: a pin or a cluster of pins. Ordered by stable id, the selected pin last.
public enum ExploreMapItem: Identifiable, Equatable, Sendable {
    case pin(ExplorePin)
    case cluster(ExploreCluster)

    public var id: String {
        switch self {
        case .pin(let p): p.id
        case .cluster(let c): c.id
        }
    }
}

/// A command for the map camera. The view applies a request when its `id` changes.
public struct CameraRequest: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// An automatic fit of the content.
        case fit(GeoRegion)
        /// A pan that keeps the zoom (selecting a spot).
        case pan(GeoRegion)
    }
    public var id: Int
    public var kind: Kind
}

/// Which surface made a selection, so the other surfaces can follow without echoing.
public enum SelectionSource: Sendable {
    case list, map, keyboard, program
}
