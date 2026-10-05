import Foundation

/// A place found by search or geocoding, before it becomes a `Spot`.
public struct PlaceResult: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var locality: String
    public var coordinate: Coordinate
    public var timeZoneIdentifier: String?
    /// MapKit point-of-interest category raw value, e.g. "MKPOICategoryNationalPark".
    public var pointOfInterestCategory: String?

    public init(id: String, name: String, locality: String, coordinate: Coordinate, timeZoneIdentifier: String?, pointOfInterestCategory: String?) {
        self.id = id
        self.name = name
        self.locality = locality
        self.coordinate = coordinate
        self.timeZoneIdentifier = timeZoneIdentifier
        self.pointOfInterestCategory = pointOfInterestCategory
    }
}

public protocol PlaceSearching: Sendable {
    /// Natural-language search ("Mesa Arch", "waterfalls"), biased to `region` when given.
    func search(_ query: String, near region: GeoRegion?) async throws -> [PlaceResult]
    /// Points of interest of the given MapKit categories within `radiusMeters` of `center`.
    func pointsOfInterest(near center: Coordinate, radiusMeters: Double, categories: [String]) async throws -> [PlaceResult]
}

public protocol Geocoding: Sendable {
    /// Name, locality and time zone for a coordinate (used when the user drops a pin).
    func reverseGeocode(_ coordinate: Coordinate) async throws -> PlaceResult
    /// Resolve a place name ("Portland, Oregon") to candidates.
    func geocode(_ query: String) async throws -> [PlaceResult]
}

// MARK: - Scout

/// Whether Apple Intelligence can run the scout, with the specific reason when it cannot.
public enum ScoutAvailability: Hashable, Sendable {
    case available
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case modelNotReady
    case unavailable(String)
}

/// One scouted place. Every one is grounded: it came from a tool result (MapKit or curated data), never from the model's memory.
public struct ScoutSuggestion: Codable, Hashable, Sendable, Identifiable {
    public enum Provenance: String, Codable, Hashable, Sendable {
        case curated
        case appleMaps
    }

    public var id: String
    public var spot: Spot
    public var provenance: Provenance
    /// The model's one-sentence reason, tied to the user's request.
    public var why: String
    /// The window the model suggests; the app scores it with the Light Index, the model does not.
    public var suggestedWindow: LightWindowKind?
    /// Drive time from the search origin, when the scout computed one.
    public var driveSeconds: TimeInterval?

    public init(id: String, spot: Spot, provenance: Provenance, why: String, suggestedWindow: LightWindowKind?, driveSeconds: TimeInterval?) {
        self.id = id
        self.spot = spot
        self.provenance = provenance
        self.why = why
        self.suggestedWindow = suggestedWindow
        self.driveSeconds = driveSeconds
    }
}

/// Progress reported while the scout runs, so the UI can show real stages and allow cancel.
public enum ScoutProgress: Hashable, Sendable {
    case understanding
    case searching(String)
    case checkingDrive(String)
    case writing
}

public protocol Scouting: Sendable {
    func availability() -> ScoutAvailability
    /// Runs one request. Cancellable via task cancellation. `progress` is called on arbitrary threads.
    func scout(_ request: String, progress: @escaping @Sendable (ScoutProgress) -> Void) async throws -> [ScoutSuggestion]
}
