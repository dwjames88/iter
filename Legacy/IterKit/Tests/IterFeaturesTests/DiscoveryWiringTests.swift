import Foundation
import Testing
import IterCore
import IterData
import IterServices
@testable import IterFeatures

private let wireNow = LocalDay(year: 2026, month: 10, day: 6).at(hour: 10, in: TimeZone(identifier: "America/Denver")!)

private func coord(_ lat: Double, _ lon: Double) -> Coordinate { Coordinate(latitude: lat, longitude: lon) }

private func box(_ lat: Double, _ lon: Double, _ dLat: Double, _ dLon: Double) -> GeoRegion {
    GeoRegion(center: coord(lat, lon), latitudeDelta: dLat, longitudeDelta: dLon)
}

private func mapsPlace(_ id: String, _ name: String, _ lat: Double, _ lon: Double, category: String? = nil) -> PlaceResult {
    PlaceResult(id: id, name: name, locality: "MT", coordinate: coord(lat, lon), timeZoneIdentifier: "America/Denver",
                pointOfInterestCategory: category)
}

private func found(_ name: String, _ lat: Double, _ lon: Double, elevation: Double? = nil, feature: FeatureKind = .peak,
                   sources: Set<DiscoverySourceID> = [.openStreetMap], links: [URL] = [], why: String? = nil) -> DiscoveredPlace {
    DiscoveredPlace(name: name, coordinate: coord(lat, lon), elevationMeters: elevation, feature: feature, sources: sources,
                    links: links, mentions: 1, why: why)
}

// MARK: - Mocks

private struct WireSearch: PlaceSearching {
    var poi: [PlaceResult] = []
    var byQuery: [String: [PlaceResult]] = [:]
    var failAll = false
    func search(_ query: String, near region: GeoRegion?) async throws -> [PlaceResult] {
        if failAll { throw MapServiceError.noResult }
        return byQuery[query] ?? []
    }
    func pointsOfInterest(near center: Coordinate, radiusMeters: Double, categories: [String]) async throws -> [PlaceResult] { [] }
    func pointsOfInterest(in region: GeoRegion, categories: [String]) async throws -> [PlaceResult] { poi }
}

private struct WireGeocoder: Geocoding {
    var candidates: [PlaceResult] = []
    func reverseGeocode(_ coordinate: Coordinate) async throws -> PlaceResult { mapsPlace("g", "Here", coordinate.latitude, coordinate.longitude) }
    func geocode(_ query: String) async throws -> [PlaceResult] { candidates }
}

/// A provider that answers with fixed places or fails.
private struct WireProvider: DiscoveryProvider {
    var id: DiscoverySourceID
    var result: Result<[DiscoveredPlace], DiscoveryError>
    func discover(in area: DiscoveryArea, feature: FeatureKind?, text: String?, settings: DiscoverySettings) async throws -> [DiscoveredPlace] {
        try result.get()
    }
}

private struct WireBoundary: BoundaryResolving {
    var polygon: GeoPolygon?
    func resolveBoundary(areaName: String, near region: GeoRegion?) async -> GeoPolygon? { polygon }
}

/// A scripted engine: the area it resolves, and what discovery answers (it can be held until released).
private final class WireDiscovery: Discovering, @unchecked Sendable { // test double; state guarded by the lock
    private let lock = NSLock()
    private var _holding: Bool
    private var _calls: [(area: DiscoveryArea, feature: FeatureKind?, settings: DiscoverySettings)] = []
    private var _resolved: [String] = []
    private var _exited = 0
    let area: DiscoveryArea?
    let outcome: Result<DiscoveryReport, any Error>

    init(area: DiscoveryArea? = nil, outcome: Result<DiscoveryReport, any Error>, hold: Bool = false) {
        self.area = area
        self.outcome = outcome
        _holding = hold
    }

    var calls: [(area: DiscoveryArea, feature: FeatureKind?, settings: DiscoverySettings)] { lock.withLock { _calls } }
    var resolved: [String] { lock.withLock { _resolved } }
    func release() { lock.withLock { _holding = false } }
    /// Calls to `discover` that have returned or thrown.
    var exited: Int { lock.withLock { _exited } }

    /// Releases the hold and waits until every started `discover` call has finished, then lets the model's
    /// continuations run: replaces a fixed sleep, so a "nothing landed" check cannot pass before the work ended.
    func releaseAndDrain() async {
        release()
        for _ in 0..<2000 where exited < calls.count { await Task.yield(); try? await Task.sleep(for: .milliseconds(1)) }
        for _ in 0..<50 { await Task.yield() }
    }

    func resolveArea(named name: String, fallbackSearch: (any PlaceSearching)?) async -> DiscoveryArea? {
        lock.withLock { _resolved.append(name) }
        return area
    }

    func discover(area: DiscoveryArea, feature: FeatureKind?, text: String?, settings: DiscoverySettings) async throws -> DiscoveryReport {
        lock.withLock { _calls.append((area, feature, settings)) }
        defer { lock.withLock { _exited += 1 } }
        while lock.withLock({ _holding }) {
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(5))
        }
        try Task.checkCancellation()
        return try outcome.get()
    }
}

private final class WireScout: Scouting, @unchecked Sendable { // test double; state guarded by the lock
    private let lock = NSLock()
    private var _holding: Bool
    private var _contexts: [ScoutContext] = []
    let proposals: [RegionProposal]

    init(proposals: [RegionProposal] = [], hold: Bool = false) {
        self.proposals = proposals
        _holding = hold
    }

    var contexts: [ScoutContext] { lock.withLock { _contexts } }
    func release() { lock.withLock { _holding = false } }
    func availability() -> ScoutAvailability { .available }
    func scout(_ request: String, progress: @escaping @Sendable (ScoutProgress) -> Void) async throws -> [ScoutSuggestion] { [] }
    func proposePlaces(in region: GeoRegion, areaName: String?) async throws -> [RegionProposal] { proposals }
    func proposePlaces(in region: GeoRegion, areaName: String?, context: ScoutContext) async throws -> [RegionProposal] {
        lock.withLock { _contexts.append(context) }
        while lock.withLock({ _holding }) {
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(5))
        }
        try Task.checkCancellation()
        return proposals
    }
}

@MainActor
private func makeWired(search: WireSearch, geocoder: WireGeocoder = WireGeocoder(), discovery: (any Discovering)?,
                       scout: (any Scouting)? = nil) throws -> ExploreModel {
    let store = IterStore(container: try IterSchema.makeContainer(inMemory: true))
    let clock: @Sendable () -> Date = { wireNow }
    let sample = CachedWeatherService(wrapping: SampleWeatherService(now: clock))
    let defaults = UserDefaults(suiteName: "DiscoveryWiringTests-\(UUID().uuidString)")!
    let app = AppModel(store: store, weather: sample, search: search, geocoder: geocoder, drives: ScoutFlatDrives(), scout: scout,
                       discovery: discovery, location: UserLocationModel(defaults: defaults), sampleWeather: sample,
                       defaults: defaults, now: { wireNow })
    return ExploreModel(app: app, searchDebounce: .zero, defaults: defaults)
}

@MainActor
private func until(_ condition: () -> Bool) async {
    for _ in 0..<600 where !condition() { try? await Task.sleep(for: .milliseconds(5)) }
}

private func report(_ places: [DiscoveredPlace], _ statuses: [DiscoverySourceID: DiscoverySourceStatus] = [:], area: DiscoveryArea) -> DiscoveryReport {
    DiscoveryReport(places: places, statuses: statuses, area: area)
}

// MARK: - Glacier fixture

/// Glacier National Park as a rectangle: 48.5...49.0 N, 114.5...113.2 W.
private let glacierPolygon = GeoPolygon(rings: [[coord(48.5, -114.5), coord(48.5, -113.2), coord(49.0, -113.2), coord(49.0, -114.5)]])
private let glacierArea = DiscoveryArea(name: "Glacier National Park", region: glacierPolygon.boundingRegion, boundary: glacierPolygon)
private let glacierCandidate = mapsPlace("glacier-np", "Glacier National Park", 48.76, -113.79, category: "MKPOICategoryNationalPark")
private let mapView = box(38.6, -109.6, 2, 2)   // somewhere else entirely, so the camera has to move

private let clevelandOSM = found("Mount Cleveland", 48.925, -113.848, elevation: 3190, sources: [.openStreetMap])
private let clevelandWiki = found("Mount Cleveland", 48.9253, -113.8478, sources: [.wikipedia],
                                  links: [URL(string: "https://en.wikipedia.org/wiki/Mount_Cleveland_(Montana)")!],
                                  why: "Highest peak in the park.")
private let siyeh = found("Siyeh Peak", 48.7, -113.7, elevation: 3225, sources: [.openStreetMap])
private let outsidePeak = found("Far Away Peak", 49.5, -112.0, elevation: 2500, sources: [.openStreetMap])

/// A real `DiscoveryEngine` over fake providers: geocoder, outline, sources, validator and merge are all the real ones.
private func glacierEngine(wikivoyageDown: Bool = false) -> DiscoveryEngine {
    DiscoveryEngine(
        providers: [WireProvider(id: .openStreetMap, result: .success([clevelandOSM, siyeh, outsidePeak])),
                    WireProvider(id: .wikipedia, result: .success([clevelandWiki])),
                    WireProvider(id: .wikivoyage, result: wikivoyageDown ? .failure(.unavailable("Server busy")) : .success([]))],
        placeSearch: WireSearch(), geocoder: WireGeocoder(candidates: [glacierCandidate]),
        boundary: WireBoundary(polygon: glacierPolygon))
}

// MARK: - Merge rules

@Suite struct DiscoveryMergeRuleTests {
    private let region = box(48.76, -113.8, 1, 1.4)

    @Test func discoveredPlaceMergesIntoAMapsResultAndKeepsElevation() {
        let maps = mapsPlace("m1", "Mount Cleveland", 48.926, -113.848)
        let merged = SearchHereMerge.merge(maps: [maps], ask: [], discovered: [clevelandOSM, clevelandWiki], region: region)
        #expect(merged.count == 1)
        let r = merged[0]
        #expect(r.place.id == "m1")                                  // Maps wins
        #expect(r.sources == [.maps, .discovery])
        #expect(r.discoverySources == [.appleMaps, .openStreetMap, .wikipedia])
        #expect(r.elevationMeters == 3190)
        #expect(r.links.count == 1)
        #expect(r.note == "Highest peak in the park.")
        #expect(r.category == .landscape)
    }

    @Test func discoveryOnlyResultsFollowMapsAndAsk() {
        let maps = mapsPlace("m1", "Logan Pass", 48.696, -113.718)
        let ask = ValidatedProposal(place: mapsPlace("a1", "Hidden Lake", 48.69, -113.74), why: "Calm water.")
        let merged = SearchHereMerge.merge(maps: [maps], ask: [ask], discovered: [siyeh], region: region)
        #expect(merged.map(\.place.name) == ["Logan Pass", "Hidden Lake", "Siyeh Peak"])
        #expect(merged[1].sources == [.ask] && merged[1].discoverySources == [.appleMaps])
        #expect(merged[2].sources == [.discovery] && merged[2].discoverySources == [.openStreetMap])
        #expect(merged[2].elevationMeters == 3225)
        #expect(merged[2].place.id.hasPrefix("discovery-"))
    }

    @Test func discoveredPlaceOutsideTheContainmentRuleIsDropped() {
        let merged = SearchHereMerge.merge(maps: [], ask: [], discovered: [clevelandOSM, outsidePeak], region: region)
        #expect(merged.map(\.place.name) == ["Mount Cleveland"])
        let none = SearchHereMerge.merge(maps: [], ask: [], discovered: [clevelandOSM], inside: { _ in false })
        #expect(none.isEmpty)
    }

    @Test func aDiscoveredPlaceWithoutACoordinateIsSkipped() {
        let nameOnly = DiscoveredPlace(name: "Somewhere", sources: [.reddit])
        #expect(SearchHereMerge.merge(maps: [], ask: [], discovered: [nameOnly], region: region).isEmpty)
    }

    @Test func askAndDiscoveryFindingOnePlaceShareIt() {
        let ask = ValidatedProposal(place: mapsPlace("a1", "Siyeh Peak", 48.7005, -113.7), why: "Big views.")
        let merged = SearchHereMerge.merge(maps: [], ask: [ask], discovered: [siyeh], region: region)
        #expect(merged.count == 1)
        #expect(merged[0].sources == [.ask, .discovery])
        #expect(merged[0].elevationMeters == 3225)
        #expect(merged[0].note == "Big views.")
    }

    @Test func featureKindsHaveSpotCategories() {
        #expect(FeatureKind.waterfall.spotCategory == .waterfall)
        #expect(FeatureKind.lighthouse.spotCategory == .coast)
        #expect(FeatureKind.peak.spotCategory == .landscape)
        #expect(Set(FeatureKind.allCases.map(\.spotCategory)).isSubset(of: Set(SpotCategory.allCases)))
    }
}

// MARK: - Typed "<feature> in <area>" searches

@MainActor
@Suite(.serialized) struct FeatureSearchTests {
    private var glacierMaps: WireSearch {
        WireSearch(byQuery: ["mountains in Glacier National Park": [
            mapsPlace("m-cleveland", "Mount Cleveland", 48.9258, -113.8482),     // also found by OSM and Wikipedia
            mapsPlace("m-logan", "Logan Pass Visitor Center", 48.696, -113.718),   // Maps only
            mapsPlace("m-brewery", "Mountain Brewing", 47.3, -111.2),             // outside the park
        ]])
    }

    @Test func mountainsInGlacierEndToEnd() async throws {
        let explore = try makeWired(search: glacierMaps, discovery: glacierEngine(wikivoyageDown: true))
        explore.cameraDidChange(to: mapView)
        explore.query = "mountains in Glacier National Park"
        explore.submitSearch()
        #expect(explore.featureStatus.isSearching || explore.featureStatus.phase == .finished)
        await until { explore.featureStatus.phase == .finished }

        // A feature section, with the rows inside the outline only.
        let section = try #require(explore.sections.first { $0.kind == .feature })
        let names = section.rows.map(\.spot.name)
        #expect(Set(names) == ["Mount Cleveland", "Siyeh Peak", "Logan Pass Visitor Center"])
        #expect(!names.contains("Far Away Peak"))        // outside the outline: dropped by the engine
        #expect(!names.contains("Mountain Brewing"))     // outside the outline: dropped from Apple Maps
        #expect(explore.sections.contains { $0.kind == .appleMaps } == false)

        // One row per place, with its sources, elevation and links.
        let cleveland = try #require(section.rows.first { $0.spot.name == "Mount Cleveland" })
        #expect(cleveland.id == "m-cleveland")
        #expect(cleveland.sources == [.appleMaps, .openStreetMap, .wikipedia])
        #expect(cleveland.elevationMeters == 3190)
        #expect(cleveland.spot.elevationMeters == 3190)
        #expect(cleveland.links.count == 1)
        let siyehRow = try #require(section.rows.first { $0.spot.name == "Siyeh Peak" })
        #expect(siyehRow.sources == [.openStreetMap])
        #expect(siyehRow.elevationMeters == 3225)
        #expect(siyehRow.spot.category == .landscape)
        let logan = try #require(section.rows.first { $0.id == "m-logan" })
        #expect(logan.sources == [.appleMaps])
        #expect(logan.elevationMeters == nil)

        // Status: what ran, what was unavailable.
        let status = explore.featureStatus
        #expect(status.feature == .peak)
        #expect(status.areaName == "Glacier National Park")
        #expect(status.hasBoundary)
        #expect(!status.areaNotFound)
        #expect(status.maps == .found(2))
        #expect(status.sources[.wikivoyage] == .unavailable("Server busy"))
        #expect(status.sources[.openStreetMap] == .ok(2))
        #expect(status.total == 3)
        #expect(explore.searchState == .finished(query: "mountains in Glacier National Park", count: 3))
        #expect(explore.featureArea?.boundary == glacierPolygon)

        // Scored by the normal Light Index path.
        for row in section.rows { _ = await explore.app.forecasts.load(row.spot.coordinate) }
        await explore.waitForScoring()
        #expect(explore.sections.first { $0.kind == .feature }?.rows.allSatisfy { $0.score != nil } == true)

        // The camera went to the results.
        guard case .fit(let region)? = explore.cameraRequest?.kind else { Issue.record("no fit request"); return }
        #expect(region.contains(cleveland.spot.coordinate))
        #expect(!region.contains(coord(47.3, -111.2)))
    }

    @Test func everyFeatureResultHasAPinAndSelectionFollowsBothWays() async throws {
        let explore = try makeWired(search: glacierMaps, discovery: glacierEngine())
        explore.cameraDidChange(to: mapView)
        explore.query = "mountains in Glacier National Park"
        explore.submitSearch()
        await until { explore.featureStatus.phase == .finished }
        let ids = Set(explore.rows.map(\.id))
        #expect(ids.count == 3)
        // Pins (or cluster members) cover every row.
        var onMap = Set<String>()
        for item in explore.mapItems {
            switch item {
            case .pin(let pin): onMap.insert(pin.id)
            case .cluster(let cluster): onMap.formUnion(cluster.memberIDs)
            }
        }
        #expect(onMap == ids)
        #expect(Set(explore.pins.map(\.id)) == ids)

        // A pin tap selects the row and asks the list to scroll to it.
        let target = try #require(ids.sorted().last)
        explore.select(target, from: .map)
        #expect(explore.selectedID == target)
        #expect(explore.selectedRow?.id == target)
        #expect(explore.scrollRequest?.target == target)
        #expect(explore.showsPanel)
        #expect(explore.pins.first { $0.id == target }?.style == .selected)

        // A row click selects the pin and pans the map to it.
        let other = try #require(ids.sorted().first)
        explore.select(other, from: .list)
        #expect(explore.selectedID == other)
        #expect(explore.pins.first { $0.id == other }?.style == .selected)
        guard case .pan? = explore.cameraRequest?.kind else { Issue.record("no pan request"); return }
    }

    @Test func discoveryAskedForTheFeatureInTheResolvedArea() async throws {
        let fake = WireDiscovery(area: glacierArea, outcome: .success(report([clevelandOSM], area: glacierArea)))
        let explore = try makeWired(search: glacierMaps, discovery: fake)
        explore.app.searchSettings.promptPrefix = "Moody peaks"
        explore.query = "all the Mountains in Glacier National Park"
        #expect(explore.featureQuery(for: explore.query)?.feature == .peak)
        explore.submitSearch()
        await until { explore.featureStatus.phase == .finished }
        #expect(fake.resolved == ["Glacier National Park"])
        let call = try #require(fake.calls.first)
        #expect(call.feature == .peak)
        #expect(call.area == glacierArea)
        #expect(call.settings.promptPrefix == "Moody peaks")
        #expect(call.settings.enabledSources.contains(.appleMaps))
    }

    @Test func waterfallsInYosemite() async throws {
        let yosemitePolygon = GeoPolygon(rings: [[coord(37.5, -119.9), coord(37.5, -119.2), coord(38.2, -119.2), coord(38.2, -119.9)]])
        let area = DiscoveryArea(name: "Yosemite National Park", region: yosemitePolygon.boundingRegion, boundary: yosemitePolygon)
        let falls = [found("Yosemite Falls", 37.7567, -119.5967, elevation: 1200, feature: .waterfall),
                     found("Bridalveil Fall", 37.7163, -119.6468, elevation: 1200, feature: .waterfall, sources: [.openStreetMap, .wikipedia])]
        let statuses: [DiscoverySourceID: DiscoverySourceStatus] = [.openStreetMap: .ok(2), .wikipedia: .ok(1), .wikivoyage: .skipped, .reddit: .unavailable("Rate limited")]
        let fake = WireDiscovery(area: area, outcome: .success(report(falls, statuses, area: area)))
        let search = WireSearch(byQuery: ["waterfalls in Yosemite": [mapsPlace("m1", "Vernal Fall", 37.7276, -119.5439),
                                                                     mapsPlace("m2", "Niagara Falls", 43.08, -79.07)]])
        let explore = try makeWired(search: search, discovery: fake)
        explore.query = "waterfalls in Yosemite"
        explore.submitSearch()
        await until { explore.featureStatus.phase == .finished }
        let rows = try #require(explore.sections.first { $0.kind == .feature }?.rows)
        #expect(Set(rows.map(\.spot.name)) == ["Yosemite Falls", "Bridalveil Fall", "Vernal Fall"])
        #expect(rows.allSatisfy { $0.spot.category == .waterfall || $0.id == "m1" })
        #expect(explore.featureStatus.feature == .waterfall)
        #expect(explore.featureStatus.sources[.reddit] == .unavailable("Rate limited"))
        #expect(rows.first { $0.spot.name == "Yosemite Falls" }?.elevationMeters == 1200)
    }

    @Test func aFailingDiscoveryKeepsAppleMapsResults() async throws {
        struct Boom: Error {}
        let fake = WireDiscovery(area: glacierArea, outcome: .failure(Boom()))
        let explore = try makeWired(search: glacierMaps, discovery: fake)
        explore.query = "mountains in Glacier National Park"
        explore.submitSearch()
        await until { explore.featureStatus.phase == .finished }
        #expect(explore.featureStatus.discoveryFailed)
        let names = explore.sections.first { $0.kind == .feature }?.rows.map(\.spot.name) ?? []
        #expect(Set(names) == ["Mount Cleveland", "Logan Pass Visitor Center"])
        #expect(explore.searchState == .finished(query: "mountains in Glacier National Park", count: 2))
    }

    @Test func mapsShowFirstWhileDiscoveryIsStillRunning() async throws {
        let fake = WireDiscovery(area: glacierArea, outcome: .success(report([siyeh], area: glacierArea)), hold: true)
        let explore = try makeWired(search: glacierMaps, discovery: fake)
        explore.query = "mountains in Glacier National Park"
        explore.submitSearch()
        await until { !explore.featureResults.isEmpty }
        #expect(explore.featureStatus.phase == .searching)
        #expect(explore.featureResults.map(\.place.name).sorted() == ["Logan Pass Visitor Center", "Mount Cleveland"])
        #expect(explore.searchState.isSearching)
        fake.release()
        await until { explore.featureStatus.phase == .finished }
        #expect(explore.featureResults.count == 3)
    }

    @Test func clearingTheFieldCancelsAndClears() async throws {
        let fake = WireDiscovery(area: glacierArea, outcome: .success(report([siyeh], area: glacierArea)), hold: true)
        let explore = try makeWired(search: glacierMaps, discovery: fake)
        explore.query = "mountains in Glacier National Park"
        explore.submitSearch()
        await until { !explore.featureResults.isEmpty }
        explore.query = ""
        #expect(explore.featureResults.isEmpty)
        #expect(explore.featureStatus == .idle)
        #expect(explore.searchState == .idle)
        await fake.releaseAndDrain()
        #expect(explore.featureResults.isEmpty)
        #expect(!explore.sections.contains { $0.kind == .feature })
    }

    @Test func aNewSubmitReplacesTheFeatureSearch() async throws {
        let fake = WireDiscovery(area: glacierArea, outcome: .success(report([siyeh], area: glacierArea)))
        var search = glacierMaps
        search.byQuery["Mesa Arch"] = [mapsPlace("arch", "Mesa Arch", 38.38, -109.87)]
        let explore = try makeWired(search: search, discovery: fake)
        explore.query = "mountains in Glacier National Park"
        explore.submitSearch()
        await until { explore.featureStatus.phase == .finished }
        explore.query = "Mesa Arch"
        explore.submitSearch()
        await until { explore.sections.contains { $0.kind == .appleMaps } }
        #expect(explore.featureResults.isEmpty)
        #expect(explore.featureStatus == .idle)
        #expect(!explore.sections.contains { $0.kind == .feature })
        #expect(explore.sections.first { $0.kind == .appleMaps }?.rows.map(\.id) == ["arch"])
        #expect(explore.sections.first { $0.kind == .appleMaps }?.rows.first?.sources == [.appleMaps])
    }

    @Test func anAreaThatCannotBeFoundFallsBackToAppleMaps() async throws {
        let fake = WireDiscovery(area: nil, outcome: .success(report([], area: glacierArea)))
        let explore = try makeWired(search: glacierMaps, discovery: fake)
        explore.query = "mountains in Glacier National Park"
        explore.submitSearch()
        await until { explore.featureStatus.phase == .finished }
        #expect(explore.featureStatus.areaNotFound)
        #expect(fake.calls.isEmpty)
        #expect(!explore.sections.contains { $0.kind == .feature })
        #expect(explore.sections.first { $0.kind == .appleMaps }?.rows.count == 3)
    }

    @Test func withoutAnEngineItIsTheOrdinarySearch() async throws {
        let explore = try makeWired(search: glacierMaps, discovery: nil)
        explore.query = "mountains in Glacier National Park"
        #expect(explore.featureQuery(for: explore.query) == nil)
        explore.submitSearch()
        await until { explore.searchState == .finished(query: "mountains in Glacier National Park", count: 3) }
        #expect(explore.featureStatus == .idle)
        #expect(explore.featureResults.isEmpty)
        #expect(explore.sections.first { $0.kind == .appleMaps }?.rows.count == 3)
    }

    @Test func withEverySourceOffItIsTheOrdinarySearch() async throws {
        let fake = WireDiscovery(area: glacierArea, outcome: .success(report([siyeh], area: glacierArea)))
        let explore = try makeWired(search: glacierMaps, discovery: fake)
        for source in SearchSettingsModel.toggleableSources { explore.app.searchSettings.setEnabled(source, false) }
        explore.query = "mountains in Glacier National Park"
        explore.submitSearch()
        await until { explore.searchState == .finished(query: "mountains in Glacier National Park", count: 3) }
        #expect(fake.resolved.isEmpty && fake.calls.isEmpty)
        #expect(explore.sections.first { $0.kind == .appleMaps }?.rows.count == 3)
    }

    @Test func plainPlaceTextIsNeverAFeatureSearch() async throws {
        let fake = WireDiscovery(area: glacierArea, outcome: .success(report([siyeh], area: glacierArea)))
        let explore = try makeWired(search: WireSearch(byQuery: ["Mesa Arch": [mapsPlace("arch", "Mesa Arch", 38.38, -109.87)]]), discovery: fake)
        explore.query = "Mesa Arch"
        explore.submitSearch()
        await until { explore.sections.contains { $0.kind == .appleMaps } }
        #expect(fake.resolved.isEmpty)
    }

    @Test func theTopSuggestionCarriesTheParsedQuery() throws {
        let with = SearchSuggestions.make(query: "peaks in Banff", askAvailability: .available, discoveryAvailable: true)
        #expect(with.first?.featureQuery == FeatureAreaQuery(feature: .peak, area: "Banff"))
        let without = SearchSuggestions.make(query: "peaks in Banff", askAvailability: .available)
        #expect(without.first?.featureQuery == nil)
        #expect(SearchSuggestions.make(query: "Mesa Arch", askAvailability: .available, discoveryAvailable: true).first?.featureQuery == nil)
        let explore = try makeWired(search: WireSearch(), discovery: glacierEngine())
        explore.query = "mountains in Glacier National Park"
        #expect(explore.searchSuggestions.first?.featureQuery?.area == "Glacier National Park")
    }

    @Test func aMapPhraseIsNeverOfferedAsAnArea() throws {
        let explore = try makeWired(search: WireSearch(), discovery: glacierEngine())
        explore.query = "waterfalls near here for sunrise"
        #expect(explore.searchSuggestions.allSatisfy { $0.featureQuery == nil })
        explore.query = "peaks in Glacier National Park at sunset"
        #expect(explore.searchSuggestions.first?.featureQuery?.area == "Glacier National Park")
    }
}

// MARK: - Search Here with Discovery

@MainActor
@Suite(.serialized) struct SearchHereDiscoveryTests {
    private let view = box(48.76, -113.8, 1, 1.4)
    private let lake = mapsPlace("lake", "Hidden Lake", 48.69, -113.74, category: "MKPOICategoryPark")

    private var search: WireSearch { WireSearch(poi: [lake]) }

    private func okReport(_ places: [DiscoveredPlace], _ statuses: [DiscoverySourceID: DiscoverySourceStatus] = [:]) -> Result<DiscoveryReport, any Error> {
        .success(report(places, statuses, area: DiscoveryArea(name: nil, region: view)))
    }

    @Test func discoveryRowsMergeWithSourcesAndElevation() async throws {
        let fake = WireDiscovery(outcome: okReport([clevelandOSM, siyeh, found("Hidden Lake", 48.6902, -113.7401, sources: [.wikipedia])],
                                                  [.openStreetMap: .ok(2), .wikipedia: .ok(1), .reddit: .unavailable("Rate limited")]))
        let explore = try makeWired(search: search, discovery: fake)
        explore.cameraDidChange(to: view)
        explore.searchHere()
        await until { explore.searchHereStatus.phase == .finished }
        let rows = try #require(explore.sections.first { $0.kind == .inView }?.rows)
        #expect(rows.map(\.spot.name) == ["Hidden Lake", "Mount Cleveland", "Siyeh Peak"])
        let hidden = rows[0]
        #expect(hidden.id == "lake")
        #expect(hidden.sources == [.appleMaps, .wikipedia])
        #expect(!hidden.viaAsk)
        #expect(rows[1].sources == [.openStreetMap] && rows[1].elevationMeters == 3190)
        #expect(rows[2].elevationMeters == 3225)
        let status = explore.searchHereStatus
        #expect(status.discoveryOutcome == .found(3))
        #expect(status.discovery[.reddit] == .unavailable("Rate limited"))
        #expect(status.total == 3)
        // The area handed to Discovery is the visible region, named by the geocoder.
        let call = try #require(fake.calls.first)
        #expect(call.area.region == view)
        #expect(call.area.boundary == nil)
        #expect(call.feature == nil)
        #expect(call.area.name == "MT")   // the locality the geocoder gave the centre
    }

    @Test func mapsShowFirstThenDiscoveryWhicheverFinishesFirst() async throws {
        let ask = WireScout(proposals: [RegionProposal(name: "Hidden Lake", why: "Calm water.")], hold: true)
        let fake = WireDiscovery(outcome: okReport([siyeh]))
        var s = search
        s.byQuery["Hidden Lake"] = [lake]
        let explore = try makeWired(search: s, discovery: fake, scout: ask)
        explore.cameraDidChange(to: view)
        explore.searchHere()
        // Discovery completes while Ask is still held.
        await until { explore.searchHereStatus.discoveryOutcome == .found(1) }
        #expect(explore.searchHereStatus.phase == .asking)
        #expect(explore.searchHereStatus.ask == .running)
        #expect(explore.sections.first { $0.kind == .inView }?.rows.map(\.spot.name) == ["Hidden Lake", "Siyeh Peak"])
        #expect(explore.sections.first { $0.kind == .inView }?.rows.first?.viaAsk == false)
        ask.release()
        await until { explore.searchHereStatus.phase == .finished }
        #expect(explore.searchHereStatus.ask == .found(1))
        let rows = try #require(explore.sections.first { $0.kind == .inView }?.rows)
        #expect(rows.map(\.spot.name) == ["Hidden Lake", "Siyeh Peak"])
        #expect(rows[0].viaAsk && rows[0].note == "Calm water.")
    }

    @Test func discoveryFailureKeepsOtherResults() async throws {
        struct Boom: Error {}
        let explore = try makeWired(search: search, discovery: WireDiscovery(outcome: .failure(Boom())))
        explore.cameraDidChange(to: view)
        explore.searchHere()
        await until { explore.searchHereStatus.phase == .finished }
        #expect(explore.searchHereStatus.discoveryOutcome == .failed)
        #expect(explore.sections.first { $0.kind == .inView }?.rows.map(\.id) == ["lake"])
    }

    @Test func aFailingSourceIsAStatusAndTheRestStay() async throws {
        let fake = WireDiscovery(outcome: okReport([siyeh], [.openStreetMap: .ok(1), .wikipedia: .unavailable("Offline")]))
        let explore = try makeWired(search: search, discovery: fake)
        explore.cameraDidChange(to: view)
        explore.searchHere()
        await until { explore.searchHereStatus.phase == .finished }
        #expect(explore.searchHereStatus.discovery[.wikipedia] == .unavailable("Offline"))
        #expect(explore.rows.contains { $0.spot.name == "Siyeh Peak" })
    }

    @Test func discoveryFindingNothingIsNone() async throws {
        let explore = try makeWired(search: search, discovery: WireDiscovery(outcome: okReport([])))
        explore.cameraDidChange(to: view)
        explore.searchHere()
        await until { explore.searchHereStatus.phase == .finished }
        #expect(explore.searchHereStatus.discoveryOutcome == .none)
    }

    @Test func noEngineMeansDiscoveryIsOffAndNothingChanges() async throws {
        let explore = try makeWired(search: search, discovery: nil)
        explore.cameraDidChange(to: view)
        explore.searchHere()
        await until { explore.searchHereStatus.phase == .finished }
        #expect(explore.searchHereStatus.discoveryOutcome == .off)
        #expect(explore.searchHereStatus.discovery.isEmpty)
        #expect(explore.searchHereStatus.ask == .unavailable(.unavailable("No scout")))
        #expect(explore.sections.first { $0.kind == .inView }?.rows.map(\.id) == ["lake"])
        #expect(explore.sections.first { $0.kind == .inView }?.rows.first?.sources == [.appleMaps])
    }

    @Test func everySourceOffMeansDiscoveryDoesNotRun() async throws {
        let fake = WireDiscovery(outcome: okReport([siyeh]))
        let explore = try makeWired(search: search, discovery: fake)
        for source in SearchSettingsModel.toggleableSources { explore.app.searchSettings.setEnabled(source, false) }
        explore.cameraDidChange(to: view)
        explore.searchHere()
        await until { explore.searchHereStatus.phase == .finished }
        #expect(explore.searchHereStatus.discoveryOutcome == .off)
        #expect(fake.calls.isEmpty)
    }

    @Test func theScoutGetsThePrefixAndTheTasteSummary() async throws {
        let ask = WireScout()
        let explore = try makeWired(search: search, discovery: nil, scout: ask)
        explore.app.searchSettings.promptPrefix = "Quiet alpine lakes"
        explore.app.store.setSaved(CuratedSpots.spot(id: "mesa-arch")!, true)
        #expect(explore.activePromptPrefix == "Quiet alpine lakes")
        explore.cameraDidChange(to: view)
        explore.searchHere()
        await until { explore.searchHereStatus.phase == .finished }
        let context = try #require(ask.contexts.first)
        #expect(context.settings.promptPrefix == "Quiet alpine lakes")
        #expect(context.settings.tasteSummary?.contains("Mesa Arch") == true)
        explore.app.searchSettings.promptPrefix = "  "
        #expect(explore.activePromptPrefix == nil)
    }

    @Test func inViewResultsHavePinsAndSelectionFollowsBothWays() async throws {
        let fake = WireDiscovery(outcome: okReport([clevelandOSM, siyeh]))
        let explore = try makeWired(search: search, discovery: fake)
        explore.cameraDidChange(to: view)
        explore.searchHere()
        await until { explore.searchHereStatus.phase == .finished }
        let ids = Set(try #require(explore.sections.first { $0.kind == .inView }).rows.map(\.id))
        #expect(ids.count == 3)
        var onMap = Set<String>()
        for item in explore.mapItems {
            switch item {
            case .pin(let pin): onMap.insert(pin.id)
            case .cluster(let cluster): onMap.formUnion(cluster.memberIDs)
            }
        }
        #expect(ids.isSubset(of: onMap))   // curated spots are on the map too
        let discoveryID = try #require(explore.rows.first { $0.spot.name == "Siyeh Peak" }?.id)
        explore.select(discoveryID, from: .map)
        #expect(explore.selectedID == discoveryID)
        #expect(explore.scrollRequest?.target == discoveryID)
        #expect(explore.pins.first { $0.id == discoveryID }?.style == .selected)
        explore.select("lake", from: .list)
        #expect(explore.pins.first { $0.id == "lake" }?.style == .selected)
        // Search Here never moves the camera by itself.
        #expect(explore.fitCoordinates.allSatisfy { c in !ids.contains { id in explore.row(id: id)?.spot.coordinate == c } })
    }

    @Test func typingCancelsAHeldDiscovery() async throws {
        let fake = WireDiscovery(outcome: okReport([siyeh]), hold: true)
        let explore = try makeWired(search: search, discovery: fake)
        explore.cameraDidChange(to: view)
        explore.searchHere()
        await until { explore.searchHereStatus.discoveryOutcome == .running }
        explore.query = "arch"
        #expect(explore.searchHereStatus == .idle)
        await fake.releaseAndDrain()
        #expect(explore.searchHereResults.isEmpty)
    }
}
