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
    /// Points of interest of the given MapKit categories inside `region`.
    /// The default searches a circle around the region's centre that reaches its corners; conformers with a native
    /// region request override it.
    func pointsOfInterest(in region: GeoRegion, categories: [String]) async throws -> [PlaceResult]
}

extension PlaceSearching {
    public func pointsOfInterest(in region: GeoRegion, categories: [String]) async throws -> [PlaceResult] {
        try await pointsOfInterest(near: region.center, radiusMeters: region.halfDiagonalMeters, categories: categories)
    }
}

extension GeoRegion {
    /// Metres from the centre to a corner of the box.
    public var halfDiagonalMeters: Double {
        let corner = Coordinate(latitude: min(90, max(-90, center.latitude + latitudeDelta / 2)),
                                longitude: center.longitude + longitudeDelta / 2)
        return center.distance(to: corner)
    }
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

/// A place name the model proposed for an area. It is not trusted until a search has found a real place of that name
/// inside the area.
public struct RegionProposal: Hashable, Sendable {
    public var name: String
    /// The model's one-sentence reason.
    public var why: String
    /// Where the model thinks it is, if it said. Never used as the place's position.
    public var approximate: Coordinate?

    public init(name: String, why: String, approximate: Coordinate? = nil) {
        self.name = name
        self.why = why
        self.approximate = approximate
    }
}

/// Thrown by a `Scouting` that cannot propose places for a region. Callers treat it as "Ask unavailable".
public enum RegionProposalError: Error, Sendable, Equatable {
    case unsupported
}

public protocol Scouting: Sendable {
    func availability() -> ScoutAvailability
    /// Runs one request. Cancellable via task cancellation. `progress` is called on arbitrary threads.
    func scout(_ request: String, progress: @escaping @Sendable (ScoutProgress) -> Void) async throws -> [ScoutSuggestion]
    /// Runs one request with the map's visible region as context: "near the map" means near `area`.
    /// The default ignores the area and calls the two-argument form, so existing conformers keep working.
    func scout(_ request: String, near area: GeoRegion?, progress: @escaping @Sendable (ScoutProgress) -> Void) async throws -> [ScoutSuggestion]
    /// Names well-known photography places inside `region`. `areaName` is a locality for context, when known.
    /// The default throws `RegionProposalError.unsupported`.
    func proposePlaces(in region: GeoRegion, areaName: String?) async throws -> [RegionProposal]
}

extension Scouting {
    /// Names well-known photography places inside `region`. `areaName` is a locality for context, when known.
    /// The default throws `RegionProposalError.unsupported`, so existing conformers keep working.
    public func proposePlaces(in region: GeoRegion, areaName: String?) async throws -> [RegionProposal] {
        throw RegionProposalError.unsupported
    }

    public func scout(_ request: String, near area: GeoRegion?, progress: @escaping @Sendable (ScoutProgress) -> Void) async throws -> [ScoutSuggestion] {
        try await scout(request, progress: progress)
    }
}
