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
    /// The headline window for the chosen intent on the chosen day; nil when the sun never makes that window.
    public var window: LightWindow?
    /// Straight-line metres from you when there is a location; else from the centre of the visible map while sorting
    /// by distance; else nil.
    public var distanceMeters: Double?

    public var id: String { spot.id }
    public var score: Int? { window?.score }

    /// Why there is no score, when there is none and the reason is specific.
    public var unavailableReason: ForecastUnavailableReason? {
        if case .noForecast(let reason)? = window?.assessment { return reason }
        return nil
    }
}

public enum ExploreSectionKind: Hashable, Sendable {
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

/// How a pin is drawn. The map has hierarchy (critique C28): one selected, a few chips, the rest dots.
public enum ExplorePinStyle: Equatable, Sendable {
    case selected
    case chip
    case dot
}

public struct ExplorePin: Identifiable, Equatable, Sendable {
    public var row: ExploreRow
    public var style: ExplorePinStyle
    public var id: String { row.id }
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
