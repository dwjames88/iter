import Foundation

/// A data source's identifier, e.g. "apple.mapkit". The ids live in the sources catalogue; this is just the typed string.
public struct SourceID: Hashable, Codable, Sendable, RawRepresentable, ExpressibleByStringLiteral, Comparable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    public var description: String { rawValue }
    public static func < (a: SourceID, b: SourceID) -> Bool { a.rawValue < b.rawValue }

    public init(from decoder: any Decoder) throws { rawValue = try decoder.singleValueContainer().decode(String.self) }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }
}

/// How authoritative a source is. Lower is more authoritative (`military` < `government` < ...).
public enum SourceTier: Int, Codable, Sendable, Comparable, CaseIterable {
    case military, government, openData, userKey, device

    public static func < (a: SourceTier, b: SourceTier) -> Bool { a.rawValue < b.rawValue }
}

/// What a source can supply.
public enum DataKind: String, Codable, Sendable, CaseIterable {
    case places, gazetteer, textEvidence, photoEvidence, geocode
    case forecast, observation, nowcast, aerosol, smoke, airQuality, satelliteCloud, lightPollution, aurora
    case astronomy, elevation, horizon, routing, eta, imagery
    // Added in Phase 2 (sources layer): official alerts, astronomical seeing, magnetic field, grid references.
    case alerts, seeing, magnetic, gridReference
    // Added in Phase 4 (discovery): real outlines of named areas (parks, protected areas).
    case boundary
}

/// The licence terms that travel with a datum.
public struct LicenceTag: Codable, Hashable, Sendable {
    /// Key of the attribution text the UI shows.
    public var key: String
    /// False when the feed's terms forbid keeping the data on disk.
    public var mayStore: Bool

    public init(key: String, mayStore: Bool) {
        self.key = key
        self.mayStore = mayStore
    }
}

/// Where a datum came from and how current it is.
public struct Provenance: Codable, Sendable, Hashable {
    public var source: SourceID
    /// e.g. the NWP model or run id.
    public var model: String?
    /// Model run or observation time.
    public var issuedAt: Date?
    public var fetchedAt: Date
    public var validFor: TimeSpan?
    /// Station or grid-point distance from the place.
    public var distanceKm: Double?
    /// Human link for citation.
    public var url: URL?
    public var licence: LicenceTag
    /// Who produced the datum and who served it (added in Phase 2; nil in data recorded before it).
    public var origin: SourceOrigin?

    public init(source: SourceID, model: String? = nil, issuedAt: Date? = nil, fetchedAt: Date, validFor: TimeSpan? = nil,
                distanceKm: Double? = nil, url: URL? = nil, licence: LicenceTag, origin: SourceOrigin? = nil) {
        self.source = source
        self.model = model
        self.issuedAt = issuedAt
        self.fetchedAt = fetchedAt
        self.validFor = validFor
        self.distanceKm = distanceKm
        self.url = url
        self.licence = licence
        self.origin = origin
    }
}

/// A value with its provenance.
public struct Sourced<Value: Sendable>: Sendable {
    public var value: Value
    public var provenance: Provenance

    public init(value: Value, provenance: Provenance) {
        self.value = value
        self.provenance = provenance
    }

    public func map<T: Sendable>(_ transform: (Value) -> T) -> Sourced<T> {
        Sourced<T>(value: transform(value), provenance: provenance)
    }
}

extension Sourced: Equatable where Value: Equatable {}
extension Sourced: Hashable where Value: Hashable {}
extension Sourced: Codable where Value: Codable {}

/// Why there is no data. Shown as a named gap, never a number.
public enum NoDataReason: Codable, Sendable, Hashable {
    case outsideCoverage
    case needsKey(SourceID)
    case offline(lastGood: Date?)
    case rateLimited(retryAfter: Date?)
    case sourceError(SourceID, String)
    case notProvidedBySource
    case appleIntelligenceUnavailable
}

/// A datum that is current, old, or missing, and says which.
public enum DataState<Value: Sendable>: Sendable {
    case fresh(Sourced<Value>)
    /// Shown with its age, never as fresh.
    case stale(Sourced<Value>, age: Duration)
    /// Shown as a named gap, never a number.
    case none([NoDataReason])

    /// The value, fresh or stale; nil when there is none.
    public var value: Value? { sourced?.value }

    public var provenance: Provenance? { sourced?.provenance }

    public var isFresh: Bool {
        if case .fresh = self { return true }
        return false
    }

    public var isStale: Bool {
        if case .stale = self { return true }
        return false
    }

    public var reasons: [NoDataReason] {
        if case .none(let reasons) = self { return reasons }
        return []
    }

    private var sourced: Sourced<Value>? {
        switch self {
        case .fresh(let s), .stale(let s, _): s
        case .none: nil
        }
    }
}

extension DataState: Equatable where Value: Equatable {}
extension DataState: Hashable where Value: Hashable {}
extension DataState: Codable where Value: Codable {}
