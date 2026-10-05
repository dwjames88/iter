import Foundation

public enum SpotCategory: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    case landscape, astro, architecture, street, coast, wildlife, desert, waterfall, forest, urban

    public var id: String { rawValue }
}

/// Where a spot came from. Shown as provenance on every card ("Curated", "Apple Maps", "Added by you", "Scout").
public enum SpotOrigin: String, Codable, CaseIterable, Hashable, Sendable {
    case curated
    case user
    case appleMaps
    case scout
}

/// A place worth shooting, as a value. The SwiftData `PlaceRecord` converts to and from this.
public struct Spot: Codable, Hashable, Sendable, Identifiable {
    /// Curated spots use their slug ("mesa-arch"); everything else a UUID string.
    public var id: String
    public var name: String
    /// Short location line, e.g. "Canyonlands National Park, UT".
    public var locality: String
    public var coordinate: Coordinate
    public var timeZoneIdentifier: String
    public var category: SpotCategory
    /// What the spot is known for, in priority order. May be empty for search results.
    public var bestLight: [BestLight]
    /// Compass bearing the classic composition faces, if known.
    public var facing: Double?
    public var blurb: String
    /// Access, gear, crowds, permits.
    public var notes: String
    /// Walk from parking to the shooting position, minutes. nil = unknown (shown as unknown, never guessed).
    public var walkInMinutes: Int?
    public var elevationMeters: Double?
    /// 0–100; high = iconic and crowded.
    public var popularity: Int
    public var tags: [String]
    public var origin: SpotOrigin

    public init(id: String, name: String, locality: String, coordinate: Coordinate, timeZoneIdentifier: String,
                category: SpotCategory, bestLight: [BestLight] = [], facing: Double? = nil, blurb: String = "",
                notes: String = "", walkInMinutes: Int? = nil, elevationMeters: Double? = nil, popularity: Int = 50,
                tags: [String] = [], origin: SpotOrigin) {
        self.id = id
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
    }

    public var timeZone: TimeZone { TimeZone(identifier: timeZoneIdentifier) ?? .current }

    /// The intent a spot defaults to: its first "best at" that is a shooting window, else sunset.
    public var defaultIntent: LightIntent {
        bestLight.lazy.compactMap(\.intent).first ?? .sunset
    }

    /// The window a new trip stop at this spot is assigned by default.
    public var defaultSession: LightWindowKind {
        switch defaultIntent {
        case .sunrise: .goldenMorning
        case .sunset: .goldenEvening
        case .blueHour: .blueEvening
        case .night: .night
        }
    }
}
