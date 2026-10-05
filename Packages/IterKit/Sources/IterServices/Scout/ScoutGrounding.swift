import Foundation
import FoundationModels
import IterCore
import OSLog

// MARK: - Model output types

@Generable
enum ScoutWindow: String, Equatable {
    case sunrise, sunset, blueHour, night, any
}

@Generable
struct ScoutPick: Equatable {
    @Guide(description: "The place ID exactly as a tool returned it, for example m3 or c:mesa-arch. Never invent an ID.")
    var placeID: String
    @Guide(description: "One short sentence on why this place suits the request, naming the light or the conditions. No numbers or coordinates.")
    var why: String
    @Guide(description: "The best light for this place given the request.")
    var window: ScoutWindow
}

@Generable
struct ScoutAnswer: Equatable {
    @Guide(description: "At most 8 picks, best first, each from a tool result.", .maximumCount(8))
    var picks: [ScoutPick]
}

// MARK: - Grounding

/// A pick as the model produced it, before it is checked against the tool results.
struct ResolvedPickInput: Sendable, Equatable {
    var placeID: String
    var why: String
    var window: ScoutWindow
}

/// The hard rule of the scout: names and coordinates come from the registry (tool results), never from model text.
enum ScoutGrounding {
    static let maximumSuggestions = 8
    static let maximumReasonLength = 240

    private static let log = Logger(subsystem: "studio.paused.iter", category: "scout")

    /// Resolves each pick against the registry. Unknown IDs are dropped (and logged); the same place is kept once, in order.
    static func resolve(picks: [ResolvedPickInput], registry: [String: RegisteredPlace], fallbackTimeZone: TimeZone = .current) -> [ScoutSuggestion] {
        var seen = Set<String>()
        var out: [ScoutSuggestion] = []
        for pick in picks {
            let key = ScoutRegistry.normalise(pick.placeID)
            guard let place = registry[key] else {
                log.notice("Dropped pick with unknown place ID \(pick.placeID, privacy: .public)")
                continue
            }
            guard seen.insert(key).inserted else { continue }

            let why = String(pick.why.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maximumReasonLength))
            let spot: Spot
            let provenance: ScoutSuggestion.Provenance
            switch place.source {
            case .curated(let curated):
                spot = curated
                provenance = .curated
            case .map(let result):
                spot = Self.spot(from: result, timeZoneIdentifier: place.resolvedTimeZoneIdentifier, fallback: fallbackTimeZone)
                provenance = .appleMaps
            }
            out.append(ScoutSuggestion(id: spot.id, spot: spot, provenance: provenance, why: why,
                                       suggestedWindow: lightWindow(for: pick.window), driveSeconds: place.driveSeconds))
            if out.count == maximumSuggestions { break }
        }
        return out
    }

    static func lightWindow(for window: ScoutWindow) -> LightWindowKind? {
        switch window {
        case .sunrise: .goldenMorning
        case .sunset: .goldenEvening
        case .blueHour: .blueEvening
        case .night: .night
        case .any: nil
        }
    }

    /// A Spot for a MapKit result: origin `.scout`, id = the MapKit place id.
    static func spot(from result: PlaceResult, timeZoneIdentifier: String?, fallback: TimeZone) -> Spot {
        Spot(id: result.id.isEmpty ? "scout:" + result.coordinate.cacheKey : result.id,
             name: result.name,
             locality: result.locality,
             coordinate: result.coordinate,
             timeZoneIdentifier: result.timeZoneIdentifier ?? timeZoneIdentifier ?? fallback.identifier,
             category: category(pointOfInterest: result.pointOfInterestCategory, name: result.name),
             origin: .scout)
    }

    /// Small private mapping from a MapKit POI category (or, failing that, a name keyword) to a Spot category.
    static func category(pointOfInterest raw: String?, name: String) -> SpotCategory {
        if let raw {
            let key = raw.replacingOccurrences(of: "MKPOICategory", with: "")
            switch key {
            case "NationalPark", "Park": return .landscape
            case "Beach", "Marina": return .coast
            case "Zoo", "Aquarium": return .wildlife
            case "Campground": return .forest
            case "Museum", "Library", "Theater", "University", "School", "Stadium", "Castle", "Landmark": return .architecture
            case "Nightlife", "Restaurant", "Cafe", "Bakery", "Brewery", "Winery", "Hotel", "Store": return .urban
            default: break
            }
        }
        let n = name.lowercased()
        let keywords: [(String, SpotCategory)] = [
            ("falls", .waterfall), ("waterfall", .waterfall), ("cascade", .waterfall),
            ("forest", .forest), ("woods", .forest), ("grove", .forest), ("redwood", .forest),
            ("beach", .coast), ("coast", .coast), ("lighthouse", .coast), ("cove", .coast), ("bay", .coast), ("harbor", .coast),
            ("desert", .desert), ("dunes", .desert), ("canyon", .desert),
            ("bridge", .architecture), ("tower", .architecture), ("cathedral", .architecture),
        ]
        return keywords.first { n.contains($0.0) }?.1 ?? .landscape
    }
}
