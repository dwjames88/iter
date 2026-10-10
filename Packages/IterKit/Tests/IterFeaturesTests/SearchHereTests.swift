import Foundation
import Testing
import IterCore
import IterData
import IterServices
@testable import IterFeatures

private let hereNow = LocalDay(year: 2026, month: 10, day: 6).at(hour: 10, in: TimeZone(identifier: "America/Denver")!)

private func region(_ lat: Double, _ lon: Double, _ dLat: Double = 1, _ dLon: Double = 1) -> GeoRegion {
    GeoRegion(center: Coordinate(latitude: lat, longitude: lon), latitudeDelta: dLat, longitudeDelta: dLon)
}

private func place(_ id: String, _ name: String, _ lat: Double = 38.6, _ lon: Double = -109.6,
                   category: String? = nil) -> PlaceResult {
    PlaceResult(id: id, name: name, locality: "Moab, UT", coordinate: Coordinate(latitude: lat, longitude: lon),
                timeZoneIdentifier: "America/Denver", pointOfInterestCategory: category)
}

private let parkCategory = "MKPOICategoryPark"

// MARK: - Mocks

private struct HereSearch: PlaceSearching {
    var poi: [PlaceResult] = []
    var poiFails = false
    /// Results by exact query text; a query listed in `failing` throws.
    var byQuery: [String: [PlaceResult]] = [:]
    var failing: Set<String> = []
    var failAll = false

    func search(_ query: String, near region: GeoRegion?) async throws -> [PlaceResult] {
        if failAll || failing.contains(query) { throw MapServiceError.noResult }
        return byQuery[query] ?? []
    }
    func pointsOfInterest(near center: Coordinate, radiusMeters: Double, categories: [String]) async throws -> [PlaceResult] { [] }
    func pointsOfInterest(in region: GeoRegion, categories: [String]) async throws -> [PlaceResult] {
        if poiFails || failAll { throw MapServiceError.noResult }
        return poi
    }
}

/// A scout whose region proposals the test controls. It can hold the answer until released.
private final class HereScout: Scouting, @unchecked Sendable { // test double; state guarded by the lock
    private let lock = NSLock()
    private var _holding: Bool
    private let availabilityValue: ScoutAvailability
    private let outcome: Result<[RegionProposal], any Error>
    private var _calls = 0
    private var _areaNames: [String?] = []

    init(availability: ScoutAvailability = .available, outcome: Result<[RegionProposal], any Error> = .success([]), hold: Bool = false) {
        availabilityValue = availability
        self.outcome = outcome
        _holding = hold
    }

    var calls: Int { lock.withLock { _calls } }
    var areaNames: [String?] { lock.withLock { _areaNames } }
    func release() { lock.withLock { _holding = false } }

    func availability() -> ScoutAvailability { availabilityValue }
    func scout(_ request: String, progress: @escaping @Sendable (ScoutProgress) -> Void) async throws -> [ScoutSuggestion] { [] }
    func proposePlaces(in region: GeoRegion, areaName: String?) async throws -> [RegionProposal] {
        lock.withLock { _calls += 1; _areaNames.append(areaName) }
        while lock.withLock({ _holding }) {
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(5))
        }
        try Task.checkCancellation()
        return try outcome.get()
    }
}

private struct NamedGeocoder: Geocoding {
    func reverseGeocode(_ coordinate: Coordinate) async throws -> PlaceResult { place("g", "Here", coordinate.latitude, coordinate.longitude) }
    func geocode(_ query: String) async throws -> [PlaceResult] { [] }
}

private let moab = region(38.6, -109.6, 1, 1)

@MainActor
private func makeHere(search: HereSearch, scout: (any Scouting)?) throws -> ExploreModel {
    let store = IterStore(container: try IterSchema.makeContainer(inMemory: true))
    let clock: @Sendable () -> Date = { hereNow }
    let sample = CachedWeatherService(wrapping: SampleWeatherService(now: clock))
    let defaults = UserDefaults(suiteName: "SearchHereTests-\(UUID().uuidString)")!
    let app = AppModel(store: store, weather: sample, search: search, geocoder: NamedGeocoder(), drives: ScoutFlatDrives(),
                       scout: scout, location: UserLocationModel(defaults: defaults), sampleWeather: sample, defaults: defaults,
                       now: { hereNow })
    return ExploreModel(app: app, searchDebounce: .zero, defaults: defaults)
}

/// Polls until `condition` holds (or two seconds pass).
@MainActor
private func until(_ condition: () -> Bool) async {
    for _ in 0..<400 where !condition() { try? await Task.sleep(for: .milliseconds(5)) }
}

// MARK: - Rules

@Suite struct SearchHereRulesTests {
    @Test func staleWithoutAListRegion() {
        #expect(SearchHereRules.isStale(listRegion: nil, visible: moab))
        #expect(!SearchHereRules.isStale(listRegion: nil, visible: nil))
        #expect(!SearchHereRules.isStale(listRegion: moab, visible: nil))
    }

    @Test func smallPanIsNotStale() {
        #expect(!SearchHereRules.isStale(listRegion: moab, visible: region(38.6 + 0.2, -109.6 - 0.2)))
        #expect(!SearchHereRules.isStale(listRegion: moab, visible: moab))
    }

    @Test func bigPanIsStale() {
        #expect(SearchHereRules.isStale(listRegion: moab, visible: region(38.6 + 0.3, -109.6)))
        #expect(SearchHereRules.isStale(listRegion: moab, visible: region(38.6, -109.6 + 0.3)))
    }

    @Test func zoomBeyondOnePointFiveIsStale() {
        #expect(SearchHereRules.isStale(listRegion: moab, visible: region(38.6, -109.6, 0.5, 0.5)))
        #expect(SearchHereRules.isStale(listRegion: moab, visible: region(38.6, -109.6, 2, 2)))
        #expect(!SearchHereRules.isStale(listRegion: moab, visible: region(38.6, -109.6, 1.2, 1.2)))
        #expect(!SearchHereRules.isStale(listRegion: moab, visible: region(38.6, -109.6, 1 / 1.2, 1 / 1.2)))
    }

    @Test func panAcrossTheAntimeridian() {
        let list = region(0, 179.9, 1, 1)
        // 0.2 degrees apart across the line: a small pan.
        #expect(!SearchHereRules.isStale(listRegion: list, visible: region(0, -179.9, 1, 1)))
        // 0.4 degrees apart across the line: a big pan.
        #expect(SearchHereRules.isStale(listRegion: list, visible: region(0, -179.7, 1, 1)))
    }
}

// MARK: - Filter

@Suite struct SearchHereFilterTests {
    @Test func scenicCategoriesPass() {
        #expect(SearchHereFilter.isPhotoWorthy(place("a", "Anything", category: "MKPOICategoryPark")))
        #expect(SearchHereFilter.isPhotoWorthy(place("b", "Anything", category: "MKPOICategoryBeach")))
        #expect(SearchHereFilter.isPhotoWorthy(place("c", "Anything", category: "MKPOICategoryNationalPark")))
    }

    @Test func otherCategoriesFailEvenWithScenicWords() {
        #expect(!SearchHereFilter.isPhotoWorthy(place("a", "Lake View Grill", category: "MKPOICategoryRestaurant")))
        #expect(!SearchHereFilter.isPhotoWorthy(place("b", "Bay Hotel", category: "MKPOICategoryHotel")))
        #expect(!SearchHereFilter.isPhotoWorthy(place("c", "Falls Store", category: "MKPOICategoryStore")))
    }

    @Test func uncategorisedNeedsAScenicWord() {
        #expect(SearchHereFilter.isPhotoWorthy(place("a", "Mirror Lake")))
        #expect(SearchHereFilter.isPhotoWorthy(place("b", "Rainbow FALLS")))
        #expect(SearchHereFilter.isPhotoWorthy(place("c", "Pointe-à-Pic Overlook")))
        #expect(!SearchHereFilter.isPhotoWorthy(place("d", "Joe's Diner")))
        // Whole words only.
        #expect(!SearchHereFilter.isPhotoWorthy(place("e", "Parking Pointless Lakeside Cafe")))
    }
}

// MARK: - Validator

@Suite struct SearchHereValidatorTests {
    private let proposal = RegionProposal(name: "Mirror Lake", why: "Still water at dawn.", approximate: nil)

    @Test func acceptsAnInRegionNameMatch() async {
        let search = HereSearch(byQuery: ["Mirror Lake": [place("m", "Mirror Lake", 38.6, -109.6)]])
        let out = await SearchHereValidator.validate([proposal], in: moab, search: search)
        #expect(out.map(\.place.id) == ["m"])
        #expect(out.first?.why == "Still water at dawn.")
    }

    @Test func rejectsAnOutOfRegionResult() async {
        let search = HereSearch(byQuery: ["Mirror Lake": [place("m", "Mirror Lake", 41, -109.6)]])
        #expect(await SearchHereValidator.validate([proposal], in: moab, search: search).isEmpty)
    }

    @Test func rejectsANameMismatch() async {
        let search = HereSearch(byQuery: ["Mirror Lake": [place("x", "Sunset Diner", 38.6, -109.6)]])
        #expect(await SearchHereValidator.validate([proposal], in: moab, search: search).isEmpty)
    }

    @Test func picksTheMatchingResultAmongSeveral() async {
        let search = HereSearch(byQuery: ["Mirror Lake": [
            place("far", "Mirror Lake", 41, -109.6),
            place("other", "Sunset Diner", 38.6, -109.6),
            place("ok", "mirror lake trailhead", 38.7, -109.5),
        ]])
        let out = await SearchHereValidator.validate([proposal], in: moab, search: search)
        #expect(out.map(\.place.id) == ["ok"])
    }

    @Test func aThrowingSearchDropsOnlyThatProposal() async {
        let search = HereSearch(byQuery: ["Mirror Lake": [place("m", "Mirror Lake")], "Delicate Arch": [place("d", "Delicate Arch")]],
                                failing: ["Boom Point"])
        let proposals = [proposal, RegionProposal(name: "Boom Point", why: "x"), RegionProposal(name: "Delicate Arch", why: "y")]
        let out = await SearchHereValidator.validate(proposals, in: moab, search: search)
        #expect(out.map(\.place.id) == ["m", "d"])
    }

    @Test func capsAtEightProposals() async {
        var byQuery: [String: [PlaceResult]] = [:]
        let proposals = (0..<12).map { RegionProposal(name: "Lake \($0)x", why: "w") }
        for p in proposals { byQuery[p.name] = [place(p.name, p.name)] }
        let out = await SearchHereValidator.validate(proposals, in: moab, search: HereSearch(byQuery: byQuery))
        #expect(out.count == 8)
    }
}

// MARK: - Merge

@Suite struct SearchHereMergeTests {
    @Test func mapsDuplicateByID() {
        let out = SearchHereMerge.merge(maps: [place("a", "Mirror Lake"), place("a", "Other", 38.9, -109.3)], ask: [], region: moab)
        #expect(out.map(\.id) == ["a"])
    }

    @Test func mapsDuplicateByNameWithinFiveHundredMetres() {
        // About 330 m apart, names overlap.
        let out = SearchHereMerge.merge(maps: [place("a", "Mirror Lake", 38.600, -109.6), place("b", "Mirror Lake Trailhead", 38.603, -109.6)],
                                        ask: [], region: moab)
        #expect(out.map(\.id) == ["a"])
        // Same distance, different names: kept.
        let kept = SearchHereMerge.merge(maps: [place("a", "Mirror Lake", 38.600, -109.6), place("b", "Eagle Peak", 38.603, -109.6)],
                                         ask: [], region: moab)
        #expect(kept.count == 2)
    }

    @Test func mapsDuplicateByProximity() {
        // About 22 m apart, unrelated names.
        let out = SearchHereMerge.merge(maps: [place("a", "Mirror Lake", 38.6000, -109.6), place("b", "Eagle Peak", 38.6002, -109.6)],
                                        ask: [], region: moab)
        #expect(out.map(\.id) == ["a"])
    }

    @Test func askDuplicateOfMapsIsOneResultWithBothSources() {
        let ask = ValidatedProposal(place: place("z", "Mirror Lake", 38.6005, -109.6), why: "Still water.")
        let out = SearchHereMerge.merge(maps: [place("a", "Mirror Lake")], ask: [ask], region: moab)
        #expect(out.count == 1)
        #expect(out[0].place.id == "a")
        #expect(out[0].sources == [.maps, .ask])
        #expect(out[0].note == "Still water.")
    }

    @Test func outOfRegionIsDropped() {
        let ask = ValidatedProposal(place: place("z", "Far Lake", 45, -109.6), why: "w")
        let out = SearchHereMerge.merge(maps: [place("a", "Far Peak", 45, -109.6)], ask: [ask], region: moab)
        #expect(out.isEmpty)
    }

    @Test func mapsFirstThenAskOnly() {
        let ask = [ValidatedProposal(place: place("z", "Eagle Peak", 38.8, -109.4), why: "View.")]
        let out = SearchHereMerge.merge(maps: [place("b", "Beach Cove", 38.4, -109.8), place("a", "Mirror Lake")], ask: ask, region: moab)
        #expect(out.map(\.id) == ["b", "a", "z"])
        #expect(out[2].sources == [.ask])
        #expect(out[0].sources == [.maps])
        #expect(out[0].note == nil)
    }
}

// MARK: - Model

@MainActor
@Suite(.serialized) struct SearchHereModelTests {
    private let lake = place("lake", "Mirror Lake", 38.6, -109.6, category: parkCategory)
    private let falls = place("falls", "Hidden Falls", 38.9, -109.3)
    private let diner = place("diner", "Joe's Diner", 38.61, -109.61, category: "MKPOICategoryRestaurant")
    private let ridge = place("ridge", "Eagle Peak", 38.3, -109.9)

    private var search: HereSearch {
        HereSearch(poi: [lake, diner], byQuery: ["waterfall": [falls]])
    }

    @Test func mapsShowFirstThenAskMergesInViewRows() async throws {
        let scout = HereScout(outcome: .success([RegionProposal(name: "Eagle Peak", why: "Open sky over the ridge.", approximate: nil),
                                                 RegionProposal(name: "Mirror Lake", why: "Calm water.", approximate: nil)]), hold: true)
        var s = search
        s.byQuery["Eagle Peak"] = [ridge]
        s.byQuery["Mirror Lake"] = [lake]
        let explore = try makeHere(search: s, scout: scout)
        explore.cameraDidChange(to: moab)
        explore.searchHere()
        #expect(explore.searchHereStatus.phase == .searchingMaps)
        await until { explore.searchHereStatus.phase == .asking }
        #expect(explore.searchHereStatus.maps == .found(2))
        #expect(explore.searchHereStatus.ask == .running)
        #expect(explore.sections.first?.kind == .inView)
        #expect(explore.sections.first?.rows.map(\.id) == ["lake", "falls"])   // the diner is not photo-worthy
        #expect(explore.sections.first?.rows.allSatisfy { !$0.viaAsk } == true)
        #expect(explore.sections.first?.rows.allSatisfy { $0.source == .appleMaps } == true)

        scout.release()
        await until { explore.searchHereStatus.phase == .finished }
        #expect(explore.searchHereStatus.ask == .found(2))
        #expect(explore.searchHereStatus.total == 3)
        let rows = try #require(explore.sections.first { $0.kind == .inView }?.rows)
        #expect(rows.map(\.id) == ["lake", "falls", "ridge"])
        #expect(rows.map(\.viaAsk) == [true, false, true])
        #expect(rows[0].note == "Calm water.")
        #expect(rows[2].note == "Open sky over the ridge.")
        // None of them is also listed elsewhere.
        #expect(explore.rows.filter { $0.id == "lake" }.count == 1)
        // The camera did not move.
        #expect(explore.cameraRequest == nil)
        #expect(explore.fitCoordinates.allSatisfy { c in !rows.contains { $0.spot.coordinate == c } })
    }

    @Test func scoutUnavailableKeepsMaps() async throws {
        let explore = try makeHere(search: search, scout: HereScout(availability: .appleIntelligenceNotEnabled))
        explore.cameraDidChange(to: moab)
        explore.searchHere()
        await until { explore.searchHereStatus.phase == .finished }
        #expect(explore.searchHereStatus.ask == .unavailable(.appleIntelligenceNotEnabled))
        #expect(explore.searchHereStatus.maps == .found(2))
        #expect(explore.searchHereResults.map(\.id) == ["lake", "falls"])
    }

    @Test func noScoutAtAllIsUnavailable() async throws {
        let explore = try makeHere(search: search, scout: nil)
        explore.cameraDidChange(to: moab)
        explore.searchHere()
        await until { explore.searchHereStatus.phase == .finished }
        guard case .unavailable = explore.searchHereStatus.ask else { Issue.record("expected unavailable"); return }
        #expect(explore.searchHereResults.count == 2)
    }

    @Test func unsupportedProposalsMeanUnavailable() async throws {
        let explore = try makeHere(search: search, scout: HereScout(outcome: .failure(RegionProposalError.unsupported)))
        explore.cameraDidChange(to: moab)
        explore.searchHere()
        await until { explore.searchHereStatus.phase == .finished }
        guard case .unavailable = explore.searchHereStatus.ask else { Issue.record("expected unavailable"); return }
    }

    @Test func aThrowingScoutFailsAskAndKeepsMaps() async throws {
        let explore = try makeHere(search: search, scout: HereScout(outcome: .failure(ScoutError.failed("boom"))))
        explore.cameraDidChange(to: moab)
        explore.searchHere()
        await until { explore.searchHereStatus.phase == .finished }
        #expect(explore.searchHereStatus.ask == .failed)
        #expect(explore.searchHereResults.map(\.id) == ["lake", "falls"])
    }

    @Test func askFindingNothingConfirmable() async throws {
        let scout = HereScout(outcome: .success([RegionProposal(name: "Nowhere Peak", why: "w")]))
        let explore = try makeHere(search: search, scout: scout)
        explore.cameraDidChange(to: moab)
        explore.searchHere()
        await until { explore.searchHereStatus.phase == .finished }
        #expect(explore.searchHereStatus.ask == .none)
        #expect(explore.searchHereResults.count == 2)
    }

    @Test func mapsFailedOnlyWhenEveryRequestFails() async throws {
        var s = search
        s.poiFails = true
        var explore = try makeHere(search: s, scout: nil)
        explore.cameraDidChange(to: moab)
        explore.searchHere()
        await until { explore.searchHereStatus.phase == .finished }
        #expect(explore.searchHereStatus.maps == .found(1))   // the waterfall query still answered

        s.failAll = true
        explore = try makeHere(search: s, scout: nil)
        explore.cameraDidChange(to: moab)
        explore.searchHere()
        await until { explore.searchHereStatus.phase == .finished }
        #expect(explore.searchHereStatus.maps == .failed)
        #expect(explore.searchHereResults.isEmpty)
    }

    @Test func noRegionIsANoOp() async throws {
        let explore = try makeHere(search: search, scout: nil)
        explore.searchHere()
        #expect(explore.searchHereStatus == .idle)
    }

    @Test func secondPressReplacesTheFirst() async throws {
        let scout = HereScout(outcome: .success([RegionProposal(name: "Eagle Peak", why: "w")]), hold: true)
        var s = search
        s.byQuery["Eagle Peak"] = [ridge]
        let explore = try makeHere(search: s, scout: scout)
        explore.cameraDidChange(to: moab)
        explore.searchHere()
        await until { explore.searchHereStatus.phase == .asking }
        let second = region(38.6, -109.55, 1, 1)
        explore.cameraDidChange(to: second, byUser: true)
        explore.searchHere()
        #expect(explore.searchHereStatus.region == second)
        #expect(explore.listRegion == second)
        scout.release()
        await until { explore.searchHereStatus.phase == .finished }
        await until { scout.calls >= 2 }
        #expect(explore.searchHereStatus.phase == .finished)
        #expect(explore.searchHereResults.map(\.id).contains("ridge"))
        #expect(scout.calls == 2)
        // One search wrote: no duplicates from a stale generation.
        #expect(Set(explore.searchHereResults.map(\.id)).count == explore.searchHereResults.count)
    }

    @Test func typingAQueryCancelsAndClears() async throws {
        let scout = HereScout(hold: true)
        let explore = try makeHere(search: search, scout: scout)
        explore.cameraDidChange(to: moab)
        explore.searchHere()
        await until { explore.searchHereStatus.phase == .asking }
        #expect(!explore.searchHereResults.isEmpty)
        explore.query = "arch"
        #expect(explore.searchHereStatus == .idle)
        #expect(explore.searchHereResults.isEmpty)
        #expect(!explore.sections.contains { $0.kind == .inView })
        scout.release()
        try await Task.sleep(for: .milliseconds(60))
        #expect(explore.searchHereStatus == .idle)
        #expect(explore.searchHereResults.isEmpty)
    }

    @Test func showsSearchHereFollowsTheMap() async throws {
        let explore = try makeHere(search: search, scout: nil)
        #expect(!explore.showsSearchHere)                       // no region yet
        explore.cameraDidChange(to: moab)                       // programmatic settle: the list matches it
        #expect(!explore.showsSearchHere)
        explore.cameraDidChange(to: region(38.6 + 0.6, -109.6), byUser: true)
        #expect(explore.showsSearchHere)
        explore.query = "arch"
        #expect(!explore.showsSearchHere)                       // text in the field
        explore.query = ""
        #expect(explore.showsSearchHere)
        explore.searchHere()
        #expect(!explore.showsSearchHere)                       // searching / just searched
        await until { explore.searchHereStatus.phase == .finished }
        #expect(!explore.showsSearchHere)
    }

    @Test func showsSearchHereWhenTheListIsEmpty() async throws {
        let explore = try makeHere(search: search, scout: nil)
        explore.filters.sources = []                            // nothing can be listed
        explore.cameraDidChange(to: moab)
        #expect(explore.rows.isEmpty)
        #expect(explore.showsSearchHere)
    }

    @Test func inViewRowsAreScored() async throws {
        let explore = try makeHere(search: search, scout: nil)
        explore.cameraDidChange(to: moab)
        explore.searchHere()
        await until { explore.searchHereStatus.phase == .finished }
        _ = await explore.app.forecasts.load(lake.coordinate)
        await explore.waitForScoring()
        let rows = try #require(explore.sections.first { $0.kind == .inView }?.rows)
        #expect(!rows.isEmpty)
        #expect(rows.first { $0.id == "lake" }?.score != nil)
    }

    @Test func aResultThatDuplicatesACuratedSpotIsDropped() async throws {
        let mesa = try #require(CuratedSpots.spot(id: "mesa-arch"))
        let dup = place("apple-mesa", "Mesa Arch", mesa.coordinate.latitude + 0.001, mesa.coordinate.longitude, category: parkCategory)
        let near = region(mesa.coordinate.latitude, mesa.coordinate.longitude, 1, 1)
        let explore = try makeHere(search: HereSearch(poi: [dup, lake.with(near)]), scout: nil)
        explore.cameraDidChange(to: near)
        explore.searchHere()
        await until { explore.searchHereStatus.phase == .finished }
        let inView = explore.sections.first { $0.kind == .inView }?.rows.map(\.id) ?? []
        #expect(!inView.contains("apple-mesa"))
        #expect(inView.contains("lake"))
        #expect(explore.rows.filter { $0.id == "mesa-arch" }.count == 1)
    }
}

private extension PlaceResult {
    /// The same place moved to the centre of `region`.
    func with(_ region: GeoRegion) -> PlaceResult {
        var copy = self
        copy.coordinate = Coordinate(latitude: region.center.latitude + 0.2, longitude: region.center.longitude + 0.2)
        return copy
    }
}
