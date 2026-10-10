import Foundation
import IterCore

/// Finds places for a feature in a named area from several free sources, checks each one, and ranks the result.
///
/// Structured sources (OpenStreetMap, Wikipedia, Wikivoyage) give names with coordinates and elevations. Text sources
/// (Reddit, and Google when the user has added a key) give posts, from which the on-device model copies place names;
/// those names are looked up with Apple Maps and dropped unless they land inside the area. No place is ever invented.
///
///     let engine = DiscoveryEngine.live(keys: KeychainDiscoveryKeyStore())
///     guard let query = FeatureAreaQuery.parse(request),
///           let area = await engine.resolveArea(named: query.area) else { return }
///     let report = try await engine.discover(area: area, feature: query.feature, text: nil, settings: settings)
public struct DiscoveryEngine: Sendable {
    /// The side, in degrees of latitude, of the box used for an area with no known outline (about 33 km).
    public static let defaultAreaSpanDegrees = 0.3

    private let providers: [any DiscoveryProvider]
    private let textSources: [any DiscoveryTextSource]
    private let extractor: (any DiscoveryExtracting)?
    private let placeSearch: any PlaceSearching
    private let geocoder: any Geocoding
    private let boundary: (any BoundaryResolving)?
    private let validator: DiscoveryValidator

    public init(providers: [any DiscoveryProvider], textSources: [any DiscoveryTextSource] = [], extractor: (any DiscoveryExtracting)? = nil,
                placeSearch: any PlaceSearching, geocoder: any Geocoding, boundary: (any BoundaryResolving)? = nil,
                maximumLookups: Int = DiscoveryValidator.defaultMaximumLookups) {
        self.providers = providers
        self.textSources = textSources
        self.extractor = extractor
        self.placeSearch = placeSearch
        self.geocoder = geocoder
        self.boundary = boundary
        self.validator = DiscoveryValidator(placeSearch: placeSearch, maximumLookups: maximumLookups)
    }

    /// Live wiring: the real network, Apple Maps, on-device Foundation Models, and an on-disk response cache.
    /// Google is included but stays idle until `keys` holds the user's own key and engine id.
    public static func live(keys: any DiscoveryKeyStore) -> DiscoveryEngine {
        let http = DiscoveryHTTP(transport: URLSessionTransport(), cache: DiscoveryCache(directory: DiscoveryCache.defaultDirectory))
        return DiscoveryEngine(
            providers: [OverpassProvider(http: http), WikipediaProvider(http: http), WikivoyageProvider(http: http)],
            textSources: [RedditSource(http: http), GoogleSearchSource(http: http, keys: keys)],
            extractor: FoundationModelsDiscoveryExtractor(),
            placeSearch: MapKitPlaceSearch(), geocoder: MapKitGeocoder(), boundary: OverpassBoundary(http: http))
    }

    // MARK: Area

    /// Finds the area's centre with the geocoder (then `fallbackSearch`, or the engine's own place search), and its
    /// outline from OpenStreetMap when there is one; the outline's bounding box then becomes the region.
    public func resolveArea(named name: String, fallbackSearch: (any PlaceSearching)? = nil) async -> DiscoveryArea? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var candidates = (try? await geocoder.geocode(trimmed)) ?? []
        if candidates.isEmpty { candidates = (try? await (fallbackSearch ?? placeSearch).search(trimmed, near: nil)) ?? [] }
        guard let pick = candidates.first(where: { DiscoveryNames.looselyMatches($0.name, trimmed) }) ?? candidates.first else { return nil }
        let span = Self.defaultAreaSpanDegrees
        let lonSpan = span / max(0.2, cos(pick.coordinate.latitude * .pi / 180))
        var region = GeoRegion(center: pick.coordinate, latitudeDelta: span, longitudeDelta: lonSpan)
        var outline: GeoPolygon?
        if let boundary, let polygon = await boundary.resolveBoundary(areaName: trimmed, near: region), !polygon.isEmpty {
            outline = polygon
            var box = polygon.boundingRegion
            box.latitudeDelta = max(box.latitudeDelta, 0.02)
            box.longitudeDelta = max(box.longitudeDelta, 0.02)
            region = box
        }
        return DiscoveryArea(name: trimmed, region: region, boundary: outline)
    }

    // MARK: Discovery

    private enum Outcome: Sendable {
        case places(DiscoverySourceID, Swift.Result<[DiscoveredPlace], DiscoveryError>)
        case texts(DiscoverySourceID, Swift.Result<[DiscoveryText], DiscoveryError>)
    }

    /// Runs every enabled source at once, extracts names from text, validates, merges and ranks.
    /// A failing source becomes a status and never fails the run; the only thing thrown is `CancellationError`.
    public func discover(area: DiscoveryArea, feature: FeatureKind?, text: String?, settings: DiscoverySettings) async throws -> DiscoveryReport {
        var statuses: [DiscoverySourceID: DiscoverySourceStatus] = [:]
        for id in DiscoverySourceID.allCases { statuses[id] = settings.enabledSources.contains(id) ? .skipped : .disabled }

        var runnable: [any DiscoveryProvider] = []
        for p in providers where settings.enabledSources.contains(p.id) {
            if let blocked = p.readiness() { statuses[p.id] = blocked } else { runnable.append(p) }
        }
        var runnableText: [any DiscoveryTextSource] = []
        for s in textSources where settings.enabledSources.contains(s.id) {
            if let blocked = s.readiness() { statuses[s.id] = blocked } else { runnableText.append(s) }
        }

        let outcomes = try await withThrowingTaskGroup(of: Outcome.self) { group -> [Outcome] in
            for p in runnable {
                group.addTask {
                    do { return .places(p.id, .success(try await p.discover(in: area, feature: feature, text: text, settings: settings))) }
                    catch { if error is CancellationError { throw error }; return .places(p.id, .failure(DiscoveryError.map(error))) }
                }
            }
            for s in runnableText {
                group.addTask {
                    do { return .texts(s.id, .success(try await s.texts(in: area, feature: feature, text: text, settings: settings))) }
                    catch { if error is CancellationError { throw error }; return .texts(s.id, .failure(DiscoveryError.map(error))) }
                }
            }
            var all: [Outcome] = []
            for try await o in group { all.append(o) }
            return all
        }

        var places: [DiscoveredPlace] = []
        var texts: [DiscoveryText] = []
        var succeeded = Set<DiscoverySourceID>()
        var textSourceIDs = Set<DiscoverySourceID>()
        for outcome in outcomes {
            switch outcome {
            case .places(let id, .success(let found)): places += found; succeeded.insert(id)
            case .places(let id, .failure(let error)): statuses[id] = Self.status(for: error)
            case .texts(let id, .success(let found)): texts += found; succeeded.insert(id); textSourceIDs.insert(id)
            case .texts(let id, .failure(let error)): statuses[id] = Self.status(for: error)
            }
        }

        if !texts.isEmpty {
            try Task.checkCancellation()
            do {
                guard let extractor else { throw DiscoveryError.unavailable("Text extraction unavailable") }
                places += try await extractor.extractPlaces(from: texts, area: area, feature: feature, settings: settings)
            } catch {
                if error is CancellationError { throw error }
                // Structured sources still count; the text sources are reported as unusable this time.
                for id in textSourceIDs { statuses[id] = .unavailable(DiscoveryError.map(error).reason); succeeded.remove(id) }
            }
        }

        try Task.checkCancellation()
        let validated = try await validator.validate(places, in: area)
        let ranked = DiscoveryMerge.mergeAll(validated.places, area: area, preference: settings.preference)
        for id in succeeded { statuses[id] = .ok(ranked.filter { $0.sources.contains(id) }.count) }
        if validated.resolved > 0 { statuses[.appleMaps] = .ok(validated.resolved) }

        return DiscoveryReport(places: Array(ranked.prefix(settings.maxResults)), statuses: statuses, area: area)
    }

    private static func status(for error: DiscoveryError) -> DiscoverySourceStatus {
        error == .notFound ? .skipped : .unavailable(error.reason)
    }
}
