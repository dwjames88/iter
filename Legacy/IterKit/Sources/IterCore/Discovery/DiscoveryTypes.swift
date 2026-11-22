import Foundation

/// Where a discovered place came from. Raw values are stable (they may be stored) and never shown to the user.
public enum DiscoverySourceID: String, CaseIterable, Codable, Hashable, Sendable {
    case appleMaps
    case reddit
    case wikipedia
    case wikivoyage
    case openStreetMap
    case google

    /// The sources that need no account or key. Google Programmable Search is not among them.
    public static let keyless: Set<DiscoverySourceID> = [.reddit, .wikipedia, .wikivoyage, .openStreetMap]
}

/// How results are ordered when there are more than the user asked for.
public enum DiscoveryPreference: String, CaseIterable, Codable, Hashable, Sendable {
    /// The most talked-about places first.
    case popular
    /// Lesser-known places first (still named and located).
    case unique
    /// Popular and unique interleaved.
    case mixed
}

/// The user's choices for discovery. Pure value; the app persists it.
public struct DiscoverySettings: Sendable, Equatable {
    public static let maxResultsRange = 5...60

    public var enabledSources: Set<DiscoverySourceID>
    public var preference: DiscoveryPreference
    /// Clamped to 5...60.
    public var maxResults: Int {
        didSet { maxResults = Self.clamp(maxResults) }
    }
    /// "What I like to shoot", the user's own words. Applied to prompts by `DiscoveryPrompt.prefixed`.
    public var promptPrefix: String
    /// A short summary of the user's recently pinned or added spots, or nil.
    public var tasteSummary: String?

    public init(enabledSources: Set<DiscoverySourceID> = DiscoverySourceID.keyless,
                preference: DiscoveryPreference = .mixed,
                maxResults: Int = 20,
                promptPrefix: String = "",
                tasteSummary: String? = nil) {
        self.enabledSources = enabledSources
        self.preference = preference
        self.maxResults = Self.clamp(maxResults)
        self.promptPrefix = promptPrefix
        self.tasteSummary = tasteSummary
    }

    static func clamp(_ n: Int) -> Int { min(Self.maxResultsRange.upperBound, max(Self.maxResultsRange.lowerBound, n)) }
}

/// A place found by discovery. A coordinate is optional only until the validator has resolved it;
/// everything in a `DiscoveryReport` has one.
public struct DiscoveredPlace: Hashable, Sendable, Identifiable {
    public var name: String
    public var coordinate: Coordinate?
    public var elevationMeters: Double?
    public var feature: FeatureKind?
    public var sources: Set<DiscoverySourceID>
    public var snippet: String?
    public var links: [URL]
    /// How much people talk about it: Reddit hits weighted by upvotes; a Wikipedia article counts as presence (1).
    public var mentions: Int
    /// One sentence on why it is worth a look, when a source or the extractor gave one.
    public var why: String?

    public init(name: String, coordinate: Coordinate? = nil, elevationMeters: Double? = nil, feature: FeatureKind? = nil,
                sources: Set<DiscoverySourceID>, snippet: String? = nil, links: [URL] = [], mentions: Int = 0, why: String? = nil) {
        self.name = name
        self.coordinate = coordinate
        self.elevationMeters = elevationMeters
        self.feature = feature
        self.sources = sources
        self.snippet = snippet
        self.links = links
        self.mentions = mentions
        self.why = why
    }

    public var id: String {
        DiscoveryNames.key(name).description + "@" + (coordinate?.cacheKey ?? "none")
    }

    /// True when a Wikipedia article exists for the place (a Wikipedia hit, or an OSM tag or link pointing at one).
    public var hasWikipediaPresence: Bool {
        sources.contains(.wikipedia) || links.contains { ($0.host ?? "").hasSuffix("wikipedia.org") }
    }
}

/// A piece of text from a text source (a Reddit post, a Google result) that may name places.
public struct DiscoveryText: Hashable, Sendable {
    public var source: DiscoverySourceID
    public var title: String
    public var body: String
    /// Upvotes for Reddit, 0 elsewhere.
    public var score: Int
    public var url: URL?

    public init(source: DiscoverySourceID, title: String, body: String = "", score: Int = 0, url: URL? = nil) {
        self.source = source
        self.title = title
        self.body = body
        self.score = score
        self.url = url
    }
}

/// What happened to one source in a discovery run.
public enum DiscoverySourceStatus: Sendable, Equatable {
    /// Worked; the associated value is how many places it contributed.
    case ok(Int)
    case disabled
    /// Needs the user's own key (Google Programmable Search) and has none.
    case needsKey
    /// Network, rate limit or server problem, with a short reason.
    case unavailable(String)
    /// Not applicable to this request (no page, nothing to look up).
    case skipped
}

/// The outcome of one discovery run.
public struct DiscoveryReport: Sendable, Equatable {
    /// Validated, inside the area, de-duplicated and ranked.
    public var places: [DiscoveredPlace]
    public var statuses: [DiscoverySourceID: DiscoverySourceStatus]
    public var area: DiscoveryArea

    public init(places: [DiscoveredPlace], statuses: [DiscoverySourceID: DiscoverySourceStatus], area: DiscoveryArea) {
        self.places = places
        self.statuses = statuses
        self.area = area
    }
}
