import Foundation

/// A link to where a fact came from, shown on a place.
public struct Citation: Codable, Hashable, Sendable {
    public var source: SourceID
    public var url: URL?
    public var title: String
    public var retrievedAt: Date
    public var licence: LicenceTag?

    public init(source: SourceID, url: URL? = nil, title: String, retrievedAt: Date, licence: LicenceTag? = nil) {
        self.source = source
        self.url = url
        self.title = title
        self.retrievedAt = retrievedAt
        self.licence = licence
    }
}

/// A place a source offered, before it is merged, verified and saved. Replaces the old `DiscoveredPlace`.
public struct PlaceCandidate: Codable, Hashable, Sendable, Identifiable {
    public var name: String
    /// nil until a validator has resolved it.
    public var coordinate: Coordinate?
    public var elevationMeters: Double?
    public var featureKinds: [FeatureKind]
    /// The source that produced this candidate.
    public var source: SourceID
    /// The source's own stable identifier for it (an OSM id, a MapKit identifier, a Wikipedia page id).
    public var externalID: String?
    public var citations: [Citation]
    /// How much people talk about it (for example Reddit hits weighted by upvotes); a Wikipedia article counts as 1.
    public var mentionCount: Int
    public var snippet: String?

    public init(name: String, coordinate: Coordinate? = nil, elevationMeters: Double? = nil, featureKinds: [FeatureKind] = [],
                source: SourceID, externalID: String? = nil, citations: [Citation] = [], mentionCount: Int = 0,
                snippet: String? = nil) {
        self.name = name
        self.coordinate = coordinate
        self.elevationMeters = elevationMeters
        self.featureKinds = featureKinds
        self.source = source
        self.externalID = externalID
        self.citations = citations
        self.mentionCount = mentionCount
        self.snippet = snippet
    }

    /// Stable across runs: the source plus its own id, falling back to the name and rounded position.
    public var id: String {
        "\(source.rawValue):" + (externalID ?? (name + "@" + (coordinate?.cacheKey ?? "none")))
    }

    private enum CodingKeys: String, CodingKey {
        case name, coordinate, elevationMeters, featureKinds, source, externalID, citations, mentionCount, snippet
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        coordinate = try c.decodeIfPresent(Coordinate.self, forKey: .coordinate)
        elevationMeters = try c.decodeIfPresent(Double.self, forKey: .elevationMeters)
        featureKinds = try c.decodeIfPresent([FeatureKind].self, forKey: .featureKinds) ?? []
        source = try c.decode(SourceID.self, forKey: .source)
        externalID = try c.decodeIfPresent(String.self, forKey: .externalID)
        citations = try c.decodeIfPresent([Citation].self, forKey: .citations) ?? []
        mentionCount = try c.decodeIfPresent(Int.self, forKey: .mentionCount) ?? 0
        snippet = try c.decodeIfPresent(String.self, forKey: .snippet)
    }
}
