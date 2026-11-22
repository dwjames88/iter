import Foundation

public enum PlaceCategory: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    case landscape, astro, architecture, street, coast, wildlife, desert, waterfall, forest, urban

    public var id: String { rawValue }
}

/// Where a place came from. Shown as provenance on every card ("Curated", "Apple Maps", "Added by you", "Scout").
public enum PlaceOrigin: String, Codable, CaseIterable, Hashable, Sendable {
    case curated
    case user
    case appleMaps
    case scout
}

/// How well a discovered place is established. `nil` on a `Place` means "not recorded" (a place from before V5).
public enum Verification: String, Codable, CaseIterable, Hashable, Sendable {
    /// Two or more independent sources agree.
    case confirmed
    case singleSource
    /// The user put it on the map themselves.
    case userPlaced
}

/// A place worth shooting, as a value. The SwiftData `PlaceRecord` converts to and from this.
public struct Place: Codable, Hashable, Sendable, Identifiable {
    /// The record id.
    public var id: UUID
    /// The catalogue slug ("mesa-arch") for curated places.
    public var curatedID: String?
    /// The MapKit or scout identifier, for places that came from a source.
    public var externalID: String?
    public var name: String
    /// Short location line, e.g. "Canyonlands National Park, UT".
    public var locality: String
    public var coordinate: Coordinate
    public var timeZoneIdentifier: String
    public var category: PlaceCategory
    /// What the place is known for, in priority order. May be empty for search results.
    public var bestLight: [BestLight]
    /// Compass bearing the classic composition faces, if known.
    public var facing: Double?
    public var blurb: String
    /// Access, gear, crowds, permits.
    public var notes: String
    /// Walk from parking to the shooting position, minutes. nil = unknown (shown as unknown, never guessed).
    public var walkInMinutes: Int?
    public var elevationMeters: Double?
    /// 0-100; high = iconic and crowded.
    public var popularity: Int
    public var tags: [String]
    public var origin: PlaceOrigin

    // Library metadata
    public var isSaved: Bool
    public var folderID: UUID?
    public var sortOrder: Double
    public var isPinned: Bool
    public var pinnedAt: Date?
    /// Defaults to `.distantPast`: this target never reads the clock, so callers stamp real dates.
    public var createdAt: Date
    public var updatedAt: Date

    // V5 provenance
    public var sources: [SourceID]
    public var citations: [Citation]
    public var verification: Verification?
    public var discoveredAt: Date?
    public var horizon: HorizonProfile?

    public init(id: UUID = UUID(), curatedID: String? = nil, externalID: String? = nil, name: String, locality: String = "",
                coordinate: Coordinate, timeZoneIdentifier: String, category: PlaceCategory, bestLight: [BestLight] = [],
                facing: Double? = nil, blurb: String = "", notes: String = "", walkInMinutes: Int? = nil,
                elevationMeters: Double? = nil, popularity: Int = 50, tags: [String] = [], origin: PlaceOrigin,
                isSaved: Bool = false, folderID: UUID? = nil, sortOrder: Double = 0, isPinned: Bool = false,
                pinnedAt: Date? = nil, createdAt: Date = .distantPast, updatedAt: Date = .distantPast,
                sources: [SourceID] = [], citations: [Citation] = [], verification: Verification? = nil,
                discoveredAt: Date? = nil, horizon: HorizonProfile? = nil) {
        self.id = id
        self.curatedID = curatedID
        self.externalID = externalID
        self.name = name
        self.locality = locality
        self.coordinate = coordinate
        self.timeZoneIdentifier = timeZoneIdentifier
        self.category = category
        self.bestLight = bestLight
        self.facing = facing
        self.blurb = blurb
        self.notes = notes
        self.walkInMinutes = walkInMinutes
        self.elevationMeters = elevationMeters
        self.popularity = popularity
        self.tags = tags
        self.origin = origin
        self.isSaved = isSaved
        self.folderID = folderID
        self.sortOrder = sortOrder
        self.isPinned = isPinned
        self.pinnedAt = pinnedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sources = sources
        self.citations = citations
        self.verification = verification
        self.discoveredAt = discoveredAt
        self.horizon = horizon
    }

    /// The identifier the old `Spot` value carried, for the legacy `.iter` v1 format and any code keyed on it: the curated
    /// slug, else the record's UUID string. This matches the old `PlaceRecord.spot` (`curatedID ?? id.uuidString`);
    /// `externalID` is deliberately not used.
    public var legacySpotID: String { curatedID ?? id.uuidString }

    public var timeZone: TimeZone { TimeZone(identifier: timeZoneIdentifier) ?? .current }

    /// The intent a place defaults to: its first "best at" that is a shooting window, else sunset.
    public var defaultIntent: LightIntent {
        bestLight.lazy.compactMap(\.intent).first ?? .sunset
    }

    /// The window a new trip stop at this place is assigned by default.
    public var defaultSession: LightWindowKind {
        switch defaultIntent {
        case .sunrise: .goldenMorning
        case .sunset: .goldenEvening
        case .blueHour: .blueEvening
        case .night: .night
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, curatedID, externalID, name, locality, coordinate, timeZoneIdentifier, category, bestLight, facing, blurb, notes
        case walkInMinutes, elevationMeters, popularity, tags, origin, isSaved, folderID, sortOrder, isPinned, pinnedAt
        case createdAt, updatedAt, sources, citations, verification, discoveredAt, horizon
    }

    /// Tolerant: only identity, name, coordinate, zone and category are required; everything else defaults when absent.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        curatedID = try c.decodeIfPresent(String.self, forKey: .curatedID)
        externalID = try c.decodeIfPresent(String.self, forKey: .externalID)
        name = try c.decode(String.self, forKey: .name)
        locality = try c.decodeIfPresent(String.self, forKey: .locality) ?? ""
        coordinate = try c.decode(Coordinate.self, forKey: .coordinate)
        timeZoneIdentifier = try c.decode(String.self, forKey: .timeZoneIdentifier)
        category = try c.decode(PlaceCategory.self, forKey: .category)
        bestLight = try c.decodeIfPresent([BestLight].self, forKey: .bestLight) ?? []
        facing = try c.decodeIfPresent(Double.self, forKey: .facing)
        blurb = try c.decodeIfPresent(String.self, forKey: .blurb) ?? ""
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        walkInMinutes = try c.decodeIfPresent(Int.self, forKey: .walkInMinutes)
        elevationMeters = try c.decodeIfPresent(Double.self, forKey: .elevationMeters)
        popularity = try c.decodeIfPresent(Int.self, forKey: .popularity) ?? 50
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        origin = try c.decodeIfPresent(PlaceOrigin.self, forKey: .origin) ?? .user
        isSaved = try c.decodeIfPresent(Bool.self, forKey: .isSaved) ?? false
        folderID = try c.decodeIfPresent(UUID.self, forKey: .folderID)
        sortOrder = try c.decodeIfPresent(Double.self, forKey: .sortOrder) ?? 0
        isPinned = try c.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        pinnedAt = try c.decodeIfPresent(Date.self, forKey: .pinnedAt)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? .distantPast
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .distantPast
        sources = try c.decodeIfPresent([SourceID].self, forKey: .sources) ?? []
        citations = try c.decodeIfPresent([Citation].self, forKey: .citations) ?? []
        verification = try c.decodeIfPresent(Verification.self, forKey: .verification)
        discoveredAt = try c.decodeIfPresent(Date.self, forKey: .discoveredAt)
        horizon = try c.decodeIfPresent(HorizonProfile.self, forKey: .horizon)
    }
}
