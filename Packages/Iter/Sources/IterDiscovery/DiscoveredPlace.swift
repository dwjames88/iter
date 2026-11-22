import Foundation
import IterModel
import IterSources

/// One line saying why a place is in the results, and who wrote it.
public struct PlaceExplanation: Sendable, Hashable {
    public var text: String
    /// True when the on-device model wrote it (and it passed the grounding checks); false for the template sentence.
    public var isModelWritten: Bool

    public init(text: String, isModelWritten: Bool) {
        self.text = text
        self.isModelWritten = isModelWritten
    }
}

/// A place Find returns. Its coordinate is a `GroundedCoordinate`: it came from a provider, never from the model.
public struct DiscoveredPlace: Sendable, Hashable, Identifiable {
    /// Stable for the same name and spot.
    public var id: String
    public var name: String
    public var coordinate: GroundedCoordinate
    public var elevationMeters: Double?
    public var featureKinds: [FeatureKind]
    /// Every source that contributed, in contribution order.
    public var sources: [SourceID]
    /// `confirmed` or `singleSource`. Places that are neither are dropped before they get here.
    public var verification: Verification
    /// Source, title, URL, retrieved date and licence for everything shown about the place; ready for `Place.citations`.
    public var citations: [Citation]
    public var mentionCount: Int
    /// Geotagged photos found near it (0 until the photo stage has looked, which only covers the top results).
    public var photoCount: Int
    public var photos: [LicensedPhoto]
    public var snippet: String?
    /// Nil until the explanation stage.
    public var why: PlaceExplanation?
    /// The visible parts of its rank.
    public var rank: RankBreakdown
    /// Straight-line distance from the user (or the area centre when there is no location), in km.
    public var distanceKm: Double?

    public init(id: String, name: String, coordinate: GroundedCoordinate, elevationMeters: Double? = nil, featureKinds: [FeatureKind],
                sources: [SourceID], verification: Verification, citations: [Citation], mentionCount: Int = 0, photoCount: Int = 0,
                photos: [LicensedPhoto] = [], snippet: String? = nil, why: PlaceExplanation? = nil, rank: RankBreakdown,
                distanceKm: Double? = nil) {
        self.id = id
        self.name = name
        self.coordinate = coordinate
        self.elevationMeters = elevationMeters
        self.featureKinds = featureKinds
        self.sources = sources
        self.verification = verification
        self.citations = citations
        self.mentionCount = mentionCount
        self.photoCount = photoCount
        self.photos = photos
        self.snippet = snippet
        self.why = why
        self.rank = rank
        self.distanceKm = distanceKm
    }

    /// A `Place` ready to save: the grounded coordinate, citations, sources and verification travel with it.
    public func makePlace(timeZoneIdentifier: String, locality: String = "", discoveredAt: Date, id: UUID = UUID()) -> Place {
        Place(id: id, externalID: nil, name: name, locality: locality, coordinate: coordinate.value, timeZoneIdentifier: timeZoneIdentifier,
              category: Self.category(for: featureKinds), blurb: why?.text ?? snippet ?? "", elevationMeters: elevationMeters,
              origin: .scout, sources: sources, citations: citations, verification: verification, discoveredAt: discoveredAt)
    }

    static func category(for kinds: [FeatureKind]) -> PlaceCategory {
        switch kinds.first {
        case .waterfall: .waterfall
        case .beach, .lighthouse: .coast
        case .castle, .bridge: .architecture
        case .arch, .canyon, .cave: .desert
        case .glacier, .peak, .lake, .hotSpring, .viewpoint, nil: .landscape
        }
    }

    static func makeID(name: String, coordinate: Coordinate) -> String {
        DiscoveryNames.normalise(name).replacingOccurrences(of: " ", with: "-") + "@" + coordinate.cacheKey
    }
}
