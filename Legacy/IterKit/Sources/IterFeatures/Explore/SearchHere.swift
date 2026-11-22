import Foundation
import IterCore
import IterServices

// Search Here: the pure rules behind the Explore button that searches the visible map region with Apple Maps and Ask.
// Everything here is plain values and functions, so it is unit-tested without a map or a model.

// MARK: - Results

/// Where a Search Here result was found.
public enum SearchHereSource: String, Hashable, Sendable, CaseIterable {
    case maps
    case ask
    /// Found by Discovery (OpenStreetMap, Wikipedia, Wikivoyage, Reddit, Google).
    case discovery
}

/// One Search Here result. A place both sources found is one result with both sources.
public struct SearchHereResult: Hashable, Sendable, Identifiable {
    public var place: PlaceResult
    public var sources: Set<SearchHereSource>
    /// Ask's (or a source's) one-sentence reason, when there is one.
    public var note: String?
    /// Every data source behind the result, as the app draws them: `.appleMaps` for anything Apple Maps lists
    /// (Ask's proposals are confirmed there), plus each Discovery source that found it.
    public var discoverySources: Set<DiscoverySourceID>
    public var elevationMeters: Double?
    /// Pages that mention the place (Wikipedia, Reddit, ...).
    public var links: [URL]
    /// What kind of place Discovery says it is; used when Apple Maps gives no category.
    public var category: SpotCategory?

    public var id: String { place.id }

    public init(place: PlaceResult, sources: Set<SearchHereSource>, note: String? = nil,
                discoverySources: Set<DiscoverySourceID>? = nil, elevationMeters: Double? = nil, links: [URL] = [],
                category: SpotCategory? = nil) {
        self.place = place
        self.sources = sources
        self.note = note
        self.discoverySources = discoverySources ?? (sources.contains(.discovery) ? [] : [.appleMaps])
        self.elevationMeters = elevationMeters
        self.links = links
        self.category = category
    }
}

/// An Ask proposal that a search confirmed: a real place, found inside the region, whose name matches.
public struct ValidatedProposal: Hashable, Sendable {
    public var place: PlaceResult
    public var why: String

    public init(place: PlaceResult, why: String) {
        self.place = place
        self.why = why
    }
}

/// Progress and outcome of the last Search Here, as facts. The app phrases them.
public struct SearchHereStatus: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case idle
        /// Apple Maps is searching.
        case searchingMaps
        /// Maps results are shown; Ask is still working.
        case asking
        case finished
    }

    public enum MapsOutcome: Equatable, Sendable {
        case pending
        case found(Int)
        /// Every Maps search failed.
        case failed
    }

    public enum AskOutcome: Equatable, Sendable {
        /// Not started yet.
        case pending
        case running
        /// How many results Ask contributed (including ones Maps also found).
        case found(Int)
        /// Ask ran and found nothing it could confirm.
        case none
        case unavailable(ScoutAvailability)
        case failed
    }

    /// Where Discovery stands.
    public enum DiscoveryOutcome: Equatable, Sendable {
        /// Not running: no engine, or every Discovery source is switched off.
        case off
        case running
        /// How many results Discovery contributed (including ones Maps or Ask also found).
        case found(Int)
        /// Discovery ran and found nothing inside the region.
        case none
        /// The run itself failed (not a single source: see `discovery`).
        case failed
    }

    public var phase: Phase = .idle
    /// The region that was searched.
    public var region: GeoRegion?
    public var maps: MapsOutcome = .pending
    public var ask: AskOutcome = .pending
    public var discoveryOutcome: DiscoveryOutcome = .off
    /// What happened to each Discovery source in the last run (`.unavailable(reason)`, `.needsKey`, `.disabled`, ...).
    /// Empty until Discovery finishes. The app says which source was unavailable from this.
    public var discovery: [DiscoverySourceID: DiscoverySourceStatus] = [:]
    /// Results listed now, after merging.
    public var total = 0

    public init() {}

    public static let idle = SearchHereStatus()

    public var isSearching: Bool { phase == .searchingMaps || phase == .asking }
}

// MARK: - Staleness

public enum SearchHereRules {
    /// The map has moved far enough that the list no longer describes it: the centre moved by more than this fraction
    /// of the list region's span on either axis.
    public static let panFraction = 0.25
    /// Or the zoom changed by more than this factor, either way.
    public static let zoomFactor = 1.5

    /// True when the visible region should offer "Search Here": there is one, and either nothing matches it yet or the
    /// list's region is well away from it.
    public static func isStale(listRegion: GeoRegion?, visible: GeoRegion?) -> Bool {
        guard let visible else { return false }
        guard let list = listRegion else { return true }
        guard list.latitudeDelta > 0, list.longitudeDelta > 0 else { return true }
        let dLat = abs(visible.center.latitude - list.center.latitude)
        var dLon = abs(visible.center.longitude - list.center.longitude).truncatingRemainder(dividingBy: 360)
        if dLon > 180 { dLon = 360 - dLon }
        if dLat > panFraction * list.latitudeDelta || dLon > panFraction * list.longitudeDelta { return true }
        let ratio = visible.latitudeDelta / list.latitudeDelta
        return ratio > zoomFactor || ratio < 1 / zoomFactor
    }
}

// MARK: - Names

enum SearchHereNames {
    /// Lowercased, diacritics removed, split into letters-and-digits words.
    static func tokens(_ name: String) -> [String] {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
    }

    static func normalised(_ name: String) -> String { tokens(name).joined(separator: " ") }

    /// Two names refer to the same place: one contains the other, or at least half the shorter name's words are shared.
    static func match(_ a: String, _ b: String) -> Bool {
        let ta = tokens(a), tb = tokens(b)
        guard !ta.isEmpty, !tb.isEmpty else { return false }
        let na = ta.joined(separator: " "), nb = tb.joined(separator: " ")
        if na == nb || na.contains(nb) || nb.contains(na) { return true }
        let shared = Set(ta).intersection(Set(tb)).count
        return Double(shared) / Double(min(Set(ta).count, Set(tb).count)) >= 0.5
    }
}

// MARK: - Filter

public enum SearchHereFilter {
    /// Words that make an otherwise uncategorised place worth a photographer's look.
    static let scenicWords: Set<String> = [
        "lake", "lakes", "falls", "waterfall", "waterfalls", "overlook", "viewpoint", "vista", "point", "peak", "mount",
        "mountain", "beach", "canyon", "arch", "park", "bay", "cove", "lighthouse", "bridge", "trail", "summit", "ridge",
        "glacier", "gorge", "dunes", "pier", "cliffs", "island",
    ]

    /// A place worth listing: a scenic MapKit category, or no category and a scenic word in the name. Restaurants,
    /// hotels, shops and other categories are never listed.
    public static func isPhotoWorthy(_ place: PlaceResult) -> Bool {
        if let category = place.pointOfInterestCategory {
            return POICategoryMapping.scenicCategories.contains(category)
        }
        return !Set(SearchHereNames.tokens(place.name)).isDisjoint(with: scenicWords)
    }
}

// MARK: - Validation

public enum SearchHereValidator {
    public static let maximumProposals = 8
    static let concurrency = 3

    /// Resolves each proposal with a search near `region` and keeps it only when a result lies inside the region and
    /// its name matches the proposal. The model's own coordinates are never used. A search that throws drops that
    /// proposal alone; cancellation stops the lot. Results are in proposal order.
    public static func validate(_ proposals: [RegionProposal], in region: GeoRegion,
                                search: any PlaceSearching) async -> [ValidatedProposal] {
        let capped = Array(proposals.prefix(maximumProposals))
        var found: [Int: ValidatedProposal] = [:]
        await withTaskGroup(of: (Int, ValidatedProposal?).self) { group in
            var next = 0
            func addNext() {
                guard next < capped.count else { return }
                let (index, proposal) = (next, capped[next])
                next += 1
                group.addTask { (index, await resolve(proposal, in: region, search: search)) }
            }
            for _ in 0..<min(concurrency, capped.count) { addNext() }
            while let (index, validated) = await group.next() {
                if let validated { found[index] = validated }
                if Task.isCancelled { group.cancelAll(); continue }
                addNext()
            }
        }
        return found.keys.sorted().compactMap { found[$0] }
    }

    private static func resolve(_ proposal: RegionProposal, in region: GeoRegion, search: any PlaceSearching) async -> ValidatedProposal? {
        let name = proposal.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !Task.isCancelled else { return nil }
        guard let results = try? await search.search(name, near: region) else { return nil }
        guard let match = results.first(where: { region.contains($0.coordinate) && SearchHereNames.match($0.name, name) }) else { return nil }
        return ValidatedProposal(place: match, why: proposal.why)
    }
}

// MARK: - Merge

extension FeatureKind {
    /// The spot category a place of this kind gets when Apple Maps gives none.
    public var spotCategory: SpotCategory {
        switch self {
        case .waterfall: .waterfall
        case .beach, .lighthouse: .coast
        case .canyon: .desert
        case .bridge, .castle: .architecture
        case .peak, .lake, .arch, .viewpoint, .glacier, .hotSpring, .cave: .landscape
        }
    }
}

public enum SearchHereMerge {
    /// Same name within this distance is the same place.
    public static let sameNameMeters = 500.0
    /// Any two places this close are the same place, whatever they are called.
    public static let anyNameMeters = 75.0

    static func isDuplicate(_ a: PlaceResult, _ b: PlaceResult) -> Bool {
        if a.id == b.id { return true }
        let distance = a.coordinate.distance(to: b.coordinate)
        if distance <= anyNameMeters { return true }
        return distance <= sameNameMeters && SearchHereNames.match(a.name, b.name)
    }

    /// Maps results first in their own order, then Ask-only results in theirs, then Discovery-only results in their
    /// ranked order. Anything outside `region` is dropped. A place found twice keeps the first entry (Maps wins) and
    /// gains the other's sources, elevation, links and reason.
    public static func merge(maps: [PlaceResult], ask: [ValidatedProposal], discovered: [DiscoveredPlace] = [],
                             locality: String = "", region: GeoRegion) -> [SearchHereResult] {
        merge(maps: maps, ask: ask, discovered: discovered, locality: locality, inside: region.contains)
    }

    /// The same merge with any containment rule (a park's real outline, for a feature search).
    public static func merge(maps: [PlaceResult], ask: [ValidatedProposal], discovered: [DiscoveredPlace] = [],
                             locality: String = "", inside: (Coordinate) -> Bool) -> [SearchHereResult] {
        var out: [SearchHereResult] = []
        for place in maps where inside(place.coordinate) {
            if out.contains(where: { isDuplicate($0.place, place) }) { continue }
            out.append(SearchHereResult(place: place, sources: [.maps]))
        }
        for proposal in ask where inside(proposal.place.coordinate) {
            let why = proposal.why.isEmpty ? nil : proposal.why
            if let i = out.firstIndex(where: { isDuplicate($0.place, proposal.place) }) {
                out[i].sources.insert(.ask)
                if out[i].note == nil { out[i].note = why }
            } else {
                out.append(SearchHereResult(place: proposal.place, sources: [.ask], note: why))
            }
        }
        for found in discovered {
            guard let coordinate = found.coordinate, inside(coordinate) else { continue }
            let place = PlaceResult(id: "discovery-" + found.id, name: found.name, locality: locality, coordinate: coordinate,
                                    timeZoneIdentifier: nil, pointOfInterestCategory: nil)
            let note = found.why ?? found.snippet
            if let i = out.firstIndex(where: { isDuplicate($0.place, place) }) {
                out[i].sources.insert(.discovery)
                out[i].discoverySources.formUnion(found.sources)
                if out[i].note == nil { out[i].note = note }
                if out[i].elevationMeters == nil { out[i].elevationMeters = found.elevationMeters }
                if out[i].category == nil { out[i].category = found.feature?.spotCategory }
                for link in found.links where !out[i].links.contains(link) { out[i].links.append(link) }
            } else {
                out.append(SearchHereResult(place: place, sources: [.discovery], note: note, discoverySources: found.sources,
                                            elevationMeters: found.elevationMeters, links: found.links,
                                            category: found.feature?.spotCategory))
            }
        }
        return out
    }
}
