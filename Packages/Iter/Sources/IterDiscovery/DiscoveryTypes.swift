import Foundation
import IterModel
import IterSources

/// How results are ordered (the owner's words: popular, unique, mixed).
public enum DiscoveryOrdering: String, Codable, Sendable, Hashable, CaseIterable {
    /// The well-known places first.
    case popular
    /// Places few people write about or photograph first.
    case unique
    /// A balance of the two.
    case mixed
}

/// A place the owner already has, for novelty ranking. Names and coordinates only: the library never leaves the device and
/// never reaches a source or the model.
public struct LibraryReference: Sendable, Hashable {
    public var name: String
    public var coordinate: Coordinate?
    public var featureKinds: [FeatureKind]

    public init(name: String, coordinate: Coordinate? = nil, featureKinds: [FeatureKind] = []) {
        self.name = name
        self.coordinate = coordinate
        self.featureKinds = featureKinds
    }
}

/// One Find.
public struct DiscoveryRequest: Sendable {
    /// What the user typed.
    public var text: String
    /// The map region the user is looking at, for "this area", and to bias geocoding.
    public var mapRegion: GeoRegion?
    /// The device location, for "near me" and for reachability.
    public var currentLocation: Coordinate?
    public var ordering: DiscoveryOrdering
    /// The owner's free-text "what I like to shoot". Matched by words, never by the model.
    public var preferenceText: String?
    public var library: [LibraryReference]
    public var maxResults: Int

    public init(text: String, mapRegion: GeoRegion? = nil, currentLocation: Coordinate? = nil, ordering: DiscoveryOrdering = .mixed,
                preferenceText: String? = nil, library: [LibraryReference] = [], maxResults: Int = 40) {
        self.text = text
        self.mapRegion = mapRegion
        self.currentLocation = currentLocation
        self.ordering = ordering
        self.preferenceText = preferenceText
        self.library = library
        self.maxResults = max(1, maxResults)
    }
}

/// Why a run produced no places at all.
public enum DiscoveryFailure: Sendable, Hashable, Error, CustomStringConvertible {
    case emptyQuery
    case area(AreaFailure)

    public var description: String {
        switch self {
        case .emptyQuery: "Type what you are looking for."
        case .area(let f): f.description
        }
    }
}

/// The end state of a run.
public struct DiscoveryResult: Sendable {
    public var request: DiscoveryRequest
    public var plan: QueryPlan
    public var planOrigin: PlanOrigin
    public var area: ResolvedArea?
    public var places: [DiscoveredPlace]
    public var statuses: [SourceStatus]
    /// Set when the run could not search at all (no area); `places` is empty then.
    public var failure: DiscoveryFailure?

    public init(request: DiscoveryRequest, plan: QueryPlan, planOrigin: PlanOrigin, area: ResolvedArea?, places: [DiscoveredPlace],
                statuses: [SourceStatus], failure: DiscoveryFailure? = nil) {
        self.request = request
        self.plan = plan
        self.planOrigin = planOrigin
        self.area = area
        self.places = places
        self.statuses = statuses
        self.failure = failure
    }
}

/// What a run streams, in this order: plan, area, status changes interleaved with partial results, then `finished` once.
public enum DiscoveryEvent: Sendable {
    case planReady(QueryPlan, PlanOrigin)
    case areaResolved(ResolvedArea)
    case statusChanged(SourceStatus)
    /// The ranked places so far (without photo counts or explanations until the last stage).
    case partial([DiscoveredPlace])
    case finished(DiscoveryResult)
}

/// Tunables. Defaults suit the app; tests shorten the timeouts.
public struct DiscoveryConfiguration: Sendable {
    /// Replaces every source's descriptor timeout when set (tests, or a global cap).
    public var sourceTimeoutOverride: Duration?
    public var planTimeout: Duration
    public var extractionTimeout: Duration
    public var explanationTimeout: Duration
    /// Merged places that get a photo-density lookup.
    public var photoLookupCount: Int
    public var photoRadiusMeters: Double
    /// Places that get a "why" line from the model.
    public var explanationCount: Int
    public var explanationConcurrency: Int
    /// Most documents handed to the extractor.
    public var maxDocuments: Int
    /// Most names geocoded after extraction.
    public var maxNamedCandidates: Int
    public var gazetteerLimit: Int

    public init(sourceTimeoutOverride: Duration? = nil, planTimeout: Duration = .seconds(10), extractionTimeout: Duration = .seconds(20),
                explanationTimeout: Duration = .seconds(10), photoLookupCount: Int = 12, photoRadiusMeters: Double = 500,
                explanationCount: Int = 10, explanationConcurrency: Int = 2, maxDocuments: Int = 24, maxNamedCandidates: Int = 15,
                gazetteerLimit: Int = 60) {
        self.sourceTimeoutOverride = sourceTimeoutOverride
        self.planTimeout = planTimeout
        self.extractionTimeout = extractionTimeout
        self.explanationTimeout = explanationTimeout
        self.photoLookupCount = photoLookupCount
        self.photoRadiusMeters = photoRadiusMeters
        self.explanationCount = explanationCount
        self.explanationConcurrency = max(1, explanationConcurrency)
        self.maxDocuments = maxDocuments
        self.maxNamedCandidates = maxNamedCandidates
        self.gazetteerLimit = gazetteerLimit
    }

    public static let `default` = DiscoveryConfiguration()

    func timeout(for descriptor: SourceDescriptor) -> Duration {
        if let o = sourceTimeoutOverride { return min(o, descriptor.timeout) }
        return descriptor.timeout
    }
}
