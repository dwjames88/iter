import Foundation
import FoundationModels
import IterCore

/// What every tool shares for one scout run.
struct ScoutToolContext: Sendable {
    var search: any PlaceSearching
    var geocoder: any Geocoding
    var drives: (any DriveTimeProviding)?
    var curated: [Spot]
    var registry: ScoutRegistry
    var progress: @Sendable (ScoutProgress) -> Void
    /// The map's visible region when the request came from Explore; "the map" resolves to its centre.
    var area: GeoRegion?

    static let maximumRows = 6
    static let radiusRange = 5.0...300.0
    /// MapKit biases to a region but does not clip to it; results further than this multiple of the radius are dropped.
    static let radiusSlack = 1.25
    static let wideSearchKilometers = 40.0
    static let cityCoreKilometers = 4.0
    static let scenicCategories = ["MKPOICategoryNationalPark", "MKPOICategoryPark", "MKPOICategoryBeach"]

    /// Words that mean "where the map is looking".
    static let mapPhrases: Set<String> = ["the map", "map", "here", "this area", "the map area", "this map", "current map", "map area"]

    static func isMapPhrase(_ name: String) -> Bool {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)).lowercased()
        return mapPhrases.contains(cleaned)
    }

    /// Resolves a place name once per run. "the map" (and "here", "this area") is the centre of `area`, never geocoded.
    func centre(for name: String) async throws -> PlaceResult? {
        if let area, Self.isMapPhrase(name) {
            return PlaceResult(id: "map-area", name: "the map area", locality: "", coordinate: area.center,
                               timeZoneIdentifier: nil, pointOfInterestCategory: nil)
        }
        if let cached = await registry.cachedGeocode(name) { return cached }
        guard let first = try await geocoder.geocode(name).first else { return nil }
        await registry.cacheGeocode(name, first)
        return first
    }

    static let searchLimitMessage = "Search limit reached. Choose your picks now from the IDs already returned."

    static func clampedRadius(_ kilometers: Int) -> Double {
        min(max(Double(kilometers), radiusRange.lowerBound), radiusRange.upperBound)
    }

    /// A box that covers `radiusKilometers` around `center`.
    static func region(around center: Coordinate, radiusKilometers: Double) -> GeoRegion {
        let latDelta = 2 * radiusKilometers / 111.0
        let cosLat = max(0.05, cos(center.latitude * .pi / 180))
        let lonDelta = min(360, 2 * radiusKilometers / (111.0 * cosLat))
        return GeoRegion(center: center, latitudeDelta: latDelta, longitudeDelta: lonDelta)
    }

    static func clip(_ text: String, _ length: Int) -> String {
        text.count <= length ? text : String(text.prefix(length - 1)) + "…"
    }

    static func kilometers(_ meters: Double) -> Int { Int((meters / 1000).rounded()) }

    static func kind(of result: PlaceResult) -> String {
        guard let raw = result.pointOfInterestCategory else { return "place" }
        let trimmed = raw.replacingOccurrences(of: "MKPOICategory", with: "")
        return trimmed.isEmpty ? "place" : trimmed
    }

    /// Runs `body`; cancellation propagates, any other failure becomes a line the model can read.
    static func guarded(_ what: String, _ body: () async throws -> String) async throws -> String {
        do {
            return try await body()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if Task.isCancelled { throw CancellationError() }
            return "\(what) failed. Try a different query or place."
        }
    }
}

// MARK: - Find places

struct FindPlacesTool: Tool {
    @Generable
    struct Arguments {
        @Guide(description: "What to look for, for example \"old-growth forest trail\" or \"waterfall\".")
        var query: String
        @Guide(description: "A place name to centre the search on, for example \"Portland, Oregon\".")
        var near: String
        @Guide(description: "Search radius in kilometres.", .range(10...300))
        var radiusKilometers: Int
    }

    let context: ScoutToolContext

    var name: String { "findPlaces" }
    var description: String {
        "Searches Apple Maps for real places near a named location. Returns a table of IDs, names, localities, kinds and distances."
    }

    func call(arguments: Arguments) async throws -> String {
        try await ScoutToolContext.guarded("Search") {
            try Task.checkCancellation()
            guard await context.registry.reserveSearchCall() else { return ScoutToolContext.searchLimitMessage }
            context.progress(.searching(arguments.near))
            guard let centre = try await context.centre(for: arguments.near) else {
                return "No place found called \"\(arguments.near)\". Try a larger, well-known place name."
            }
            let radius = ScoutToolContext.clampedRadius(arguments.radiusKilometers)
            let region = ScoutToolContext.region(around: centre.coordinate, radiusKilometers: radius)

            var results = try await Self.searchAround(centre.coordinate, radiusKilometers: radius, query: Self.featureQuery(arguments.query), search: context.search, fallbackRegion: region)
            try Task.checkCancellation()
            results = Self.rank(Self.within(results, of: centre.coordinate, radiusKilometers: radius))

            var rows: [String] = []
            for result in results.prefix(ScoutToolContext.maximumRows) {
                let km = ScoutToolContext.kilometers(centre.coordinate.distance(to: result.coordinate))
                let summary = "\(ScoutToolContext.clip(result.name, 36)) | \(ScoutToolContext.clip(result.locality, 24)) | \(ScoutToolContext.kind(of: result)) | \(km) km"
                let place = await context.registry.register(result, summary: summary)
                rows.append("\(place.id) | \(summary)")
            }
            guard !rows.isEmpty else {
                return "No places found for \"\(arguments.query)\" within \(Int(radius)) km of \(arguments.near). Try a more specific feature (waterfall, state park, trailhead, viewpoint) or a larger radius."
            }
            return "id | name | locality | kind | distance from \(arguments.near)\n" + rows.joined(separator: "\n")
        }
    }

    /// MapKit favours matches near the middle of the region. For wide searches, also search around four points
    /// half way to the edge so the results are not all in the city centre. Each point gets a text search and a
    /// scenic points-of-interest search, because text search alone matches street names ("Foggy Ct"). Duplicates are merged.
    static func searchAround(_ centre: Coordinate, radiusKilometers: Double, query: String, search: any PlaceSearching, fallbackRegion: GeoRegion) async throws -> [PlaceResult] {
        var centres: [(Coordinate, Double)] = [(centre, radiusKilometers)]
        if radiusKilometers >= ScoutToolContext.wideSearchKilometers {
            let offset = radiusKilometers * 0.55
            let cosLat = max(0.05, cos(centre.latitude * .pi / 180))
            let half = radiusKilometers * 0.5
            centres += [
                (Coordinate(latitude: centre.latitude + offset / 111.0, longitude: centre.longitude), half),
                (Coordinate(latitude: centre.latitude - offset / 111.0, longitude: centre.longitude), half),
                (Coordinate(latitude: centre.latitude, longitude: centre.longitude + offset / (111.0 * cosLat)), half),
                (Coordinate(latitude: centre.latitude, longitude: centre.longitude - offset / (111.0 * cosLat)), half),
            ]
        }
        // Slots: text search then points of interest, per centre. A failed slot only loses that slot,
        // unless every slot fails, in which case the first error is thrown. Cancellation always propagates.
        var slots: [[PlaceResult]] = Array(repeating: [], count: centres.count * 2)
        var firstError: (any Error)?
        var failures = 0
        await withTaskGroup(of: (Int, Result<[PlaceResult], any Error>).self) { group in
            for (i, entry) in centres.enumerated() {
                let (c, km) = entry
                let region = i == 0 ? fallbackRegion : ScoutToolContext.region(around: c, radiusKilometers: km)
                group.addTask { (i * 2, await Self.capture { try await search.search(query, near: region) }) }
                group.addTask {
                    (i * 2 + 1, await Self.capture { try await search.pointsOfInterest(near: c, radiusMeters: km * 1000, categories: ScoutToolContext.scenicCategories) })
                }
            }
            for await (slot, result) in group {
                switch result {
                case .success(let found): slots[slot] = found
                case .failure(let error): failures += 1; firstError = firstError ?? error
                }
            }
        }
        if firstError is CancellationError { throw CancellationError() }
        if failures == slots.count, let firstError { throw firstError }
        try Task.checkCancellation()
        return slots.reduce([]) { merge($0, $1) }
    }

    private static let moodWords: Set<String> = ["foggy", "fog", "misty", "mist", "moody", "dramatic", "sunrise", "sunset", "golden", "atmospheric", "hazy", "stormy", "best", "beautiful", "scenic"]

    /// MapKit text search matches names, so mood words pull in "Foggy Ct" and "Wildlife Ln". Keeps the feature words only.
    static func featureQuery(_ query: String) -> String {
        let kept = query.split(separator: " ").filter { !moodWords.contains($0.lowercased()) }
        return kept.isEmpty ? query : kept.joined(separator: " ")
    }

    private static func capture(_ body: () async throws -> [PlaceResult]) async -> Result<[PlaceResult], any Error> {
        do { return .success(try await body()) } catch { return .failure(error) }
    }

    /// Results with a points-of-interest category first (real, named places), the rest after; each group keeps its order.
    static func rank(_ results: [PlaceResult]) -> [PlaceResult] {
        results.filter { $0.pointOfInterestCategory != nil } + results.filter { $0.pointOfInterestCategory == nil }
    }

    /// Keeps results inside the radius. For wide searches it also drops results within a few kilometres of the centre:
    /// MapKit favours the nearest matches, which for a city name are its downtown parks, not places worth a trip.
    static func within(_ results: [PlaceResult], of centre: Coordinate, radiusKilometers: Double) -> [PlaceResult] {
        let minimum = radiusKilometers >= ScoutToolContext.wideSearchKilometers ? ScoutToolContext.cityCoreKilometers * 1000 : 0
        return results.filter {
            let d = centre.distance(to: $0.coordinate)
            return d <= radiusKilometers * 1000 * ScoutToolContext.radiusSlack && d >= minimum
        }
    }

    static func merge(_ a: [PlaceResult], _ b: [PlaceResult]) -> [PlaceResult] {
        var seen = Set(a.map { $0.id.isEmpty ? $0.name + $0.coordinate.cacheKey : $0.id })
        var out = a
        for r in b where seen.insert(r.id.isEmpty ? r.name + r.coordinate.cacheKey : r.id).inserted { out.append(r) }
        return out
    }
}

// MARK: - Curated spots

@Generable
enum ScoutCategoryChoice: String, CaseIterable {
    case landscape, astro, architecture, street, coast, wildlife, desert, waterfall, forest, urban

    var spotCategory: SpotCategory { SpotCategory(rawValue: rawValue) ?? .landscape }
}

@Generable
enum ScoutLightChoice: String, CaseIterable {
    case sunrise, sunset, blueHour, night

    var bestLight: BestLight { BestLight(rawValue: rawValue) ?? .sunrise }
}

struct CuratedSpotsTool: Tool {
    @Generable
    struct Arguments {
        @Guide(description: "A place name to centre on, for example \"Portland, Oregon\".")
        var near: String
        @Guide(description: "Search radius in kilometres.", .range(10...300))
        var radiusKilometers: Int
        @Guide(description: "Only spots of this category. Leave out for any.")
        var category: ScoutCategoryChoice?
        @Guide(description: "Only spots known for this light. Leave out for any.")
        var light: ScoutLightChoice?
    }

    let context: ScoutToolContext

    var name: String { "curatedSpots" }
    var description: String {
        "Lists hand-picked photography spots near a named location, with the light each is best at.."
    }

    func call(arguments: Arguments) async throws -> String {
        try await ScoutToolContext.guarded("Curated lookup") {
            try Task.checkCancellation()
            guard await context.registry.reserveSearchCall() else { return ScoutToolContext.searchLimitMessage }
            context.progress(.searching(arguments.near))
            guard let centre = try await context.centre(for: arguments.near) else {
                return "No place found called \"\(arguments.near)\"."
            }
            let radius = ScoutToolContext.clampedRadius(arguments.radiusKilometers)
            func nearby(_ filtered: Bool) -> [Spot] {
                context.curated
                    .filter { centre.coordinate.distance(to: $0.coordinate) <= radius * 1000 }
                    .filter { !filtered || arguments.category == nil || $0.category == arguments.category?.spotCategory }
                    .filter { !filtered || arguments.light == nil || $0.bestLight.contains(arguments.light?.bestLight ?? .sunrise) }
                    .sorted { centre.coordinate.distance(to: $0.coordinate) < centre.coordinate.distance(to: $1.coordinate) }
            }
            // The model often over-filters; if the filters match nothing, show everything in range rather than nothing.
            let strict = nearby(true)
            let relaxed = strict.isEmpty && (arguments.category != nil || arguments.light != nil)
            let matches = relaxed ? nearby(false) : strict
            var rows: [String] = []
            for spot in matches.prefix(ScoutToolContext.maximumRows) {
                let km = ScoutToolContext.kilometers(centre.coordinate.distance(to: spot.coordinate))
                let light = spot.bestLight.map(\.rawValue).joined(separator: "/")
                let blurb = ScoutToolContext.clip(spot.blurb.replacingOccurrences(of: "\n", with: " "), 60)
                let summary = "\(ScoutToolContext.clip(spot.name, 36)) | \(spot.category.rawValue) | best: \(light.isEmpty ? "unknown" : light) | \(km) km | \(blurb)"
                let place = await context.registry.registerCurated(spot, summary: summary)
                rows.append("\(place.id) | \(summary)")
            }
            guard !rows.isEmpty else {
                return "No curated spots match within \(Int(radius)) km of \(arguments.near). Use findPlaces instead."
            }
            let note = relaxed ? "(no exact match for the filters; showing all curated spots in range)\n" : ""
            return note + "id | name | category | best light | distance | note\n" + rows.joined(separator: "\n")
        }
    }
}

// MARK: - Drive time

struct DriveTimeTool: Tool {
    @Generable
    struct Arguments {
        @Guide(description: "The place name to drive from, for example \"Portland, Oregon\".")
        var from: String
        @Guide(description: "The ID of a place returned by another tool, for example m3.")
        var placeID: String
    }

    let context: ScoutToolContext

    var name: String { "driveTime" }
    var description: String {
        "Gives the driving time in minutes from a named place to one place already returned by a tool. Limited to a few calls; use it only for the best candidates."
    }

    func call(arguments: Arguments) async throws -> String {
        guard let drives = context.drives else { return "Drive times are not available." }
        return try await ScoutToolContext.guarded("Drive time") {
            try Task.checkCancellation()
            guard let place = await context.registry.place(arguments.placeID) else {
                return "Unknown place ID \"\(arguments.placeID)\". Use an ID from a tool result."
            }
            guard await context.registry.reserveDriveCall() else {
                return "Drive time limit reached. Do not call this tool again."
            }
            context.progress(.checkingDrive(place.name))
            guard let origin = try await context.centre(for: arguments.from) else {
                return "No place found called \"\(arguments.from)\"."
            }
            let leg = try await drives.drive(from: origin.coordinate, to: place.coordinate)
            try Task.checkCancellation()
            await context.registry.recordDrive(id: place.id, seconds: leg.seconds)
            let minutes = Int((leg.seconds / 60).rounded())
            return "\(place.id) \(place.name): about \(minutes) min drive from \(arguments.from)\(leg.isEstimate ? " (estimate)" : "")."
        }
    }
}
