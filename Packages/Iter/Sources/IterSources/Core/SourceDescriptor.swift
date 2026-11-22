import Foundation
import IterModel

/// Every provider describes itself; the registry filters and ranks on this alone.
public protocol SourceDescribing: Sendable {
    var descriptor: SourceDescriptor { get }
}

/// Where a source has data. Coarse on purpose: it decides whether to ask, not what the answer is.
public enum Coverage: Sendable, Hashable {
    case global
    /// Axis-aligned boxes (a point inside any box is covered).
    case regions([GeoRegion])
    /// Polygons (even-odd per polygon; a point inside any polygon is covered).
    case polygons([GeoPolygon])
    /// Union of several coverages.
    indirect case union([Coverage])

    public func contains(_ c: Coordinate) -> Bool {
        switch self {
        case .global: true
        case .regions(let boxes): boxes.contains { $0.contains(c) }
        case .polygons(let polygons): polygons.contains { $0.contains(c) }
        case .union(let parts): parts.contains { $0.contains(c) }
        }
    }
}

/// Whether a source needs a user's key.
public enum KeyRequirement: Sendable, Hashable {
    case none
    case optional(SourceID)
    case required(SourceID)
}

/// How politely to call a host. One policy per source; `SourceHTTP` applies it per host.
public struct RequestPolicy: Sendable, Hashable {
    /// Minimum gap between the starts of two requests to the same host.
    public var spacing: Duration
    /// Most requests in flight to the same host at once.
    public var maxConcurrent: Int
    /// Optional cap per rolling minute for the host (e.g. 100 for aviationweather.gov).
    public var perMinute: Int?
    /// Client-side timeout for one attempt. Must exceed any server-side query timeout we send (Overpass).
    public var timeout: Duration
    /// Retries after the first attempt, only for 429, 502, 503, 504, timeouts and dropped connections.
    public var maxRetries: Int
    /// First backoff; doubles each retry with jitter, capped at 60 s. A `Retry-After` header wins when present.
    public var initialBackoff: Duration
    /// Send `If-None-Match` / `If-Modified-Since` from the last response to the same URL, and reuse its body on 304.
    public var conditional: Bool
    /// Do not call the network again before the last response's `Expires` (MET Norway's terms require this).
    public var honourExpires: Bool

    public init(spacing: Duration = .milliseconds(500), maxConcurrent: Int = 2, perMinute: Int? = nil,
                timeout: Duration = .seconds(20), maxRetries: Int = 2, initialBackoff: Duration = .seconds(2),
                conditional: Bool = true, honourExpires: Bool = false) {
        self.spacing = spacing
        self.maxConcurrent = max(1, maxConcurrent)
        self.perMinute = perMinute
        self.timeout = timeout
        self.maxRetries = max(0, maxRetries)
        self.initialBackoff = initialBackoff
        self.conditional = conditional
        self.honourExpires = honourExpires
    }
}

/// One row of the source catalogue: identity, origin, what it supplies, where, how politely, how long to keep.
public struct SourceDescriptor: Sendable, Hashable, Identifiable {
    public var id: SourceID
    /// Display name, e.g. "NOAA HRRR and GFS".
    public var name: String
    /// Operator, e.g. "NOAA NCEP".
    public var operatorName: String
    /// Selection tier. For mixed feeds (METAR) this is the best origin the feed can supply, as SOURCES.md labels it;
    /// each datum's `Provenance.origin` says what it really is.
    public var tier: SourceTier
    public var origin: SourceOrigin
    public var kinds: Set<DataKind>
    public var coverage: Coverage
    public var key: KeyRequirement
    public var policy: RequestPolicy
    /// After this a cached result is stale (served with its age while one refetch runs).
    public var cacheTTL: Duration
    public var licence: LicenceTag
    public var termsURL: URL?
    /// Rank within a tier per kind; lower is preferred. Kinds not listed rank 100.
    public var ranks: [DataKind: Int]
    /// Disabled by default (the user can enable it). Used for sources whose terms are not yet read.
    public var enabledByDefault: Bool

    public init(id: SourceID, name: String, operatorName: String, tier: SourceTier, origin: SourceOrigin, kinds: Set<DataKind>,
                coverage: Coverage, key: KeyRequirement = .none, policy: RequestPolicy = RequestPolicy(),
                cacheTTL: Duration, licence: LicenceTag, termsURL: URL? = nil, ranks: [DataKind: Int] = [:],
                enabledByDefault: Bool = true) {
        self.id = id
        self.name = name
        self.operatorName = operatorName
        self.tier = tier
        self.origin = origin
        self.kinds = kinds
        self.coverage = coverage
        self.key = key
        self.policy = policy
        self.cacheTTL = cacheTTL
        self.licence = licence
        self.termsURL = termsURL
        self.ranks = ranks
        self.enabledByDefault = enabledByDefault
    }

    public func rank(for kind: DataKind) -> Int { ranks[kind] ?? 100 }

    /// The spacing and timeout callers usually want, as a convenience.
    public var spacing: Duration { policy.spacing }
    public var timeout: Duration { policy.timeout }

    /// A provenance stub for a datum fetched now from this source (callers fill model, issuedAt, distance, url).
    public func provenance(fetchedAt: Date, model: String? = nil, issuedAt: Date? = nil, validFor: TimeSpan? = nil,
                           distanceKm: Double? = nil, url: URL? = nil, origin: SourceOrigin? = nil) -> Provenance {
        Provenance(source: id, model: model, issuedAt: issuedAt, fetchedAt: fetchedAt, validFor: validFor,
                   distanceKm: distanceKm, url: url, licence: licence, origin: origin ?? self.origin)
    }
}
