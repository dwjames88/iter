import Foundation
import Testing
import IterCore
import IterData
import IterServices
@testable import IterFeatures

private let denver = TimeZone(identifier: "America/Denver")!
private let fixedNow = LocalDay(year: 2026, month: 10, day: 6).at(hour: 10, in: denver)

private struct FakeSearch: PlaceSearching {
    var results: [PlaceResult] = []
    var fails = false
    func search(_ query: String, near region: GeoRegion?) async throws -> [PlaceResult] {
        if fails { throw MapServiceError.noResult }
        return results
    }
    func pointsOfInterest(near center: Coordinate, radiusMeters: Double, categories: [String]) async throws -> [PlaceResult] { [] }
}

private struct NoDrives: DriveTimeProviding {
    func drive(from a: Coordinate, to b: Coordinate) async throws -> DriveLeg { DriveLeg.estimate(from: a, to: b) }
}

private struct NoGeocoder: Geocoding {
    func reverseGeocode(_ coordinate: Coordinate) async throws -> PlaceResult { throw MapServiceError.noResult }
    func geocode(_ query: String) async throws -> [PlaceResult] { [] }
}

private struct DownWeather: WeatherProviding {
    var source: ForecastSource { .appleWeather }
    func forecast(for coordinate: Coordinate) async throws -> Forecast { throw WeatherError.notEnabled }
    func attribution() async -> WeatherAttributionInfo? { nil }
}

/// A device-like provider: authorized, but the fix only arrives after a few yields (and after the first camera).
@MainActor
private final class LateLocation: UserLocationProviding {
    let fix: Coordinate
    var authorization: LocationAuthorization { .authorized }
    var onAuthorizationChange: (@MainActor (LocationAuthorization) -> Void)?
    init(_ fix: Coordinate) { self.fix = fix }
    func requestAuthorization() {}
    func requestFix() async -> Coordinate? {
        for _ in 0..<5 { await Task.yield() }
        return fix
    }
}

@MainActor
private func makeExplore(search: FakeSearch = FakeSearch(), weatherDown: Bool = false,
                         at fix: Coordinate? = nil, lateFix: Coordinate? = nil, radius: Int? = nil,
                         savedCamera: (region: GeoRegion, byUser: Bool)? = nil) async throws -> ExploreModel {
    let store = IterStore(container: try IterSchema.makeContainer(inMemory: true))
    let clock: @Sendable () -> Date = { fixedNow }
    let sample = CachedWeatherService(wrapping: SampleWeatherService(now: clock))
    let defaults = UserDefaults(suiteName: "ExploreTests-\(UUID().uuidString)")!
    if let savedCamera {
        var policy = MapCameraPolicy()
        if savedCamera.byUser {
            policy.cameraSettled(savedCamera.region, byUser: true)
        } else {
            policy.didApplyFit(savedCamera.region)
            policy.cameraSettled(savedCamera.region)
        }
        policy.save(screen: ExploreModel.cameraScreenKey, defaults: defaults)
    }
    let location = fix.map { UserLocationModel(provider: FixedLocationProvider($0), isSimulated: true, defaults: defaults) }
        ?? lateFix.map { UserLocationModel(provider: LateLocation($0), defaults: defaults) }
        ?? UserLocationModel(defaults: defaults)
    if let radius { location.radiusMiles = radius }
    let app = AppModel(store: store, weather: weatherDown ? DownWeather() : sample, search: search, geocoder: NoGeocoder(),
                       drives: NoDrives(), scout: nil, location: location, sampleWeather: sample, defaults: defaults, now: { fixedNow })
    let explore = ExploreModel(app: app, searchDebounce: .zero, defaults: defaults)
    explore.day = LocalDay(year: 2026, month: 10, day: 6)
    if fix != nil {
        explore.start()
        for _ in 0..<200 where location.coordinate == nil { await Task.yield() }
    }
    return explore
}

private func place(_ id: String, _ name: String, lat: Double = 38.7, lon: Double = -109.6) -> PlaceResult {
    PlaceResult(id: id, name: name, locality: "Moab, UT", coordinate: Coordinate(latitude: lat, longitude: lon),
                timeZoneIdentifier: "America/Denver", pointOfInterestCategory: nil)
}

@MainActor
@Suite struct ExploreModelTests {
    @Test func listsAllCuratedSpotsWithAHeadlineWindow() async throws {
        let explore = try await makeExplore()
        #expect(explore.rows.count == CuratedSpots.all.count)
        _ = await explore.app.forecasts.load(CuratedSpots.all[0].coordinate)
        let row = try #require(explore.row(id: CuratedSpots.all[0].id))
        #expect(row.window != nil)
        #expect(row.source == .curated)
    }

    @Test func textFilterMatchesNameLocalityAndTagsIgnoringCase() async throws {
        let explore = try await makeExplore()
        explore.query = "mesa arch"
        #expect(explore.rows.map(\.id).contains("mesa-arch"))
        #expect(explore.rows.allSatisfy { $0.spot.name.localizedCaseInsensitiveContains("mesa") || $0.spot.locality.localizedCaseInsensitiveContains("mesa") || $0.spot.tags.contains { $0.localizedCaseInsensitiveContains("mesa") } })
        explore.query = "MESA ARCH"
        #expect(explore.row(id: "mesa-arch") != nil)
        explore.query = "zzzzqq"
        #expect(explore.rows.isEmpty)
    }

    @Test func categoryAndSourceFilters() async throws {
        let explore = try await makeExplore()
        let desert = CuratedSpots.all.filter { $0.category == .desert }
        explore.filters.categories = [.desert]
        #expect(Set(explore.rows.map(\.id)) == Set(desert.map(\.id)))
        #expect(explore.filters.activeCount == 1)
        explore.filters.sources = [.yours]
        #expect(explore.rows.isEmpty)
        #expect(explore.filters.activeCount == 2)
        explore.clearFilters()
        #expect(explore.filters.activeCount == 0)
        #expect(explore.rows.count == CuratedSpots.all.count)
    }

    @Test func bestLightFilterKeepsSpotsKnownForIt() async throws {
        let explore = try await makeExplore()
        explore.filters.bestLight = [.night]
        #expect(!explore.rows.isEmpty)
        #expect(explore.rows.allSatisfy { $0.spot.bestLight.contains(.night) })
    }

    @Test func yourSpotsAreListedAndSourceFiltered() async throws {
        let explore = try await makeExplore()
        let record = explore.app.store.createUserSpot(name: "My Pull-off", coordinate: Coordinate(latitude: 38.5, longitude: -109.5),
                                                      timeZoneIdentifier: "America/Denver")
        #expect(explore.row(id: record.spot.id)?.source == .yours)
        explore.filters.sources = [.yours]
        #expect(explore.rows.map(\.id) == [record.spot.id])
    }

    @Test func bestLightSortPutsScoredFirstAndUnscoredLast() async throws {
        let explore = try await makeExplore()
        // Only some spots have a forecast loaded; the rest are still "not loaded".
        for spot in CuratedSpots.all.prefix(5) { _ = await explore.app.forecasts.load(spot.coordinate) }
        explore.sort = .bestLight
        let scores = explore.rows.map(\.score)
        let firstUnscored = try #require(scores.firstIndex { $0 == nil })
        #expect(scores[..<firstUnscored].allSatisfy { $0 != nil })
        #expect(scores[firstUnscored...].allSatisfy { $0 == nil })
        let scored = scores.compactMap { $0 }
        #expect(scored == scored.sorted(by: >))
        #expect(!scored.isEmpty)
    }

    @Test func nameAndPopularitySort() async throws {
        let explore = try await makeExplore()
        explore.sort = .name
        let names = explore.rows.map(\.spot.name)
        #expect(names == names.sorted { $0.localizedStandardCompare($1) == .orderedAscending })
        explore.sort = .popularity
        let pops = explore.rows.map(\.spot.popularity)
        #expect(pops == pops.sorted(by: >))
    }

    @Test func distanceSortUsesTheVisibleCentre() async throws {
        let explore = try await makeExplore()
        let tunnelView = try #require(CuratedSpots.spot(id: "tunnel-view"))
        explore.cameraDidChange(to: GeoRegion(center: tunnelView.coordinate, latitudeDelta: 1, longitudeDelta: 1))
        explore.sort = .distance
        #expect(explore.rows.first?.id == "tunnel-view")
        let distances = explore.rows.compactMap(\.distanceMeters)
        #expect(distances == distances.sorted())
    }

    @Test func noForecastRowsCarryTheReasonAndTheNoticeIsOneLine() async throws {
        let explore = try await makeExplore(weatherDown: true)
        for spot in CuratedSpots.all { _ = await explore.app.forecasts.load(spot.coordinate) }
        #expect(explore.rows.allSatisfy { $0.score == nil })
        // A sunrise window earlier today is honestly "passed"; everything else names the missing service.
        #expect(explore.rows.allSatisfy { $0.unavailableReason == .weatherServiceNotEnabled || $0.unavailableReason == .inThePast })
        #expect(explore.forecastNotice == .weatherServiceNotEnabled)
        #expect(!explore.isLoadingForecasts)
    }

    @Test func searchTransitionsIdleSearchingFinished() async throws {
        let explore = try await makeExplore(search: FakeSearch(results: [place("am1", "Delicate Arch Viewpoint"), place("am2", "Park Avenue")]))
        #expect(explore.searchState == .idle)
        explore.query = "arch"
        explore.submitSearch()
        #expect(explore.searchState == .searching(query: "arch"))
        await explore.searchTask?.value
        #expect(explore.searchState == .finished(query: "arch", count: 2))
        let apple = explore.sections.first { $0.kind == .appleMaps }
        #expect(apple?.rows.count == 2)
        #expect(apple?.rows.allSatisfy { $0.source == .appleMaps && $0.spot.bestLight.isEmpty } == true)
        explore.query = ""
        #expect(explore.searchState == .idle)
        #expect(explore.sections.allSatisfy { $0.kind != .appleMaps })
    }

    @Test func emptySearchIsFinishedWithZeroNotFailed() async throws {
        let explore = try await makeExplore(search: FakeSearch(results: []))
        explore.query = "nowhere at all"
        explore.submitSearch()
        await explore.searchTask?.value
        #expect(explore.searchState == .finished(query: "nowhere at all", count: 0))
    }

    @Test func searchFailureIsReportedAndRetryable() async throws {
        let explore = try await makeExplore(search: FakeSearch(fails: true))
        explore.query = "arch"
        explore.submitSearch()
        await explore.searchTask?.value
        #expect(explore.searchState == .failed(query: "arch"))
        explore.submitSearch()
        #expect(explore.searchState == .searching(query: "arch"))
        await explore.searchTask?.value
        #expect(explore.searchState == .failed(query: "arch"))
    }

    @Test func clearingTheFieldCancelsAnInFlightSearch() async throws {
        let explore = try await makeExplore(search: FakeSearch(results: [place("am1", "Late Result")]))
        explore.searchDebounce = .seconds(30)
        explore.query = "late"
        explore.submitSearch()
        let task = try #require(explore.searchTask)
        explore.query = ""
        #expect(task.isCancelled)
        await task.value
        #expect(explore.searchState == .idle)
        #expect(explore.appleResults.isEmpty)
    }

    @Test func appleMapsResultsWithoutZoneBorrowTheNearestCuratedZone() async throws {
        let explore = try await makeExplore()
        var p = place("x", "Somewhere", lat: 36.1, lon: -112.1)
        p.timeZoneIdentifier = nil
        #expect(explore.spot(from: p).timeZoneIdentifier == CuratedSpots.all.min { $0.coordinate.distance(to: p.coordinate) < $1.coordinate.distance(to: p.coordinate) }?.timeZoneIdentifier)
    }

    @Test func selectionFromTheListPansOnlyWhenOutOfView() async throws {
        let explore = try await makeExplore()
        let mesa = try #require(CuratedSpots.spot(id: "mesa-arch"))
        explore.cameraDidChange(to: GeoRegion(center: mesa.coordinate, latitudeDelta: 2, longitudeDelta: 2))
        explore.select("mesa-arch", from: .list)
        #expect(explore.selectedID == "mesa-arch")
        #expect(explore.cameraRequest == nil)
        let far = try #require(CuratedSpots.spot(id: "tunnel-view"))
        explore.select("tunnel-view", from: .list)
        guard case .pan(let target)? = explore.cameraRequest?.kind else { Issue.record("expected a pan"); return }
        // The pan keeps the zoom and brings the pin into view.
        #expect(target.latitudeDelta == 2 && target.longitudeDelta == 2)
        #expect(target.contains(far.coordinate))
    }

    @Test func selectionFromTheMapScrollsTheListAndDoesNotPan() async throws {
        let explore = try await makeExplore()
        explore.select("mesa-arch", from: .map)
        #expect(explore.scrollRequest?.target == "mesa-arch")
        #expect(explore.cameraRequest == nil)
    }

    @Test func filteringOutTheSelectionClearsIt() async throws {
        let explore = try await makeExplore()
        explore.select("mesa-arch")
        explore.filters.categories = [.waterfall]
        #expect(explore.selectedID == nil)
    }

    @Test func fitIsRequestedWhenTheResultSetChanges() async throws {
        let explore = try await makeExplore()
        explore.requestInitialCamera()
        let first = try #require(explore.cameraRequest)
        explore.filters.categories = [.desert]
        let second = try #require(explore.cameraRequest)
        #expect(second.id > first.id)
        guard case .fit(let region) = second.kind else { Issue.record("expected a fit"); return }
        for spot in CuratedSpots.all where spot.category == .desert { #expect(region.contains(spot.coordinate)) }
    }

    private static let sanFrancisco = Coordinate(latitude: 37.77, longitude: -122.42)

    private func nearYouCoordinates(_ explore: ExploreModel) -> [Coordinate] {
        explore.sections.first { $0.kind == .nearYou }?.rows.map(\.spot.coordinate) ?? []
    }

    @Test func simulatedLocationFramesNearYouFromTheFirstCamera() async throws {
        let explore = try await makeExplore(at: Self.sanFrancisco)
        let near = nearYouCoordinates(explore)
        #expect(!near.isEmpty && near.count < CuratedSpots.all.count)
        #expect(explore.initialCameraRegion == MapCameraPolicy.fit(near))
        #expect(explore.initialCameraRegion != MapCameraPolicy.fit(CuratedSpots.all.map(\.coordinate)))
    }

    @Test func simulatedLocationIsKnownBeforeStart() async throws {
        let model = UserLocationModel(provider: FixedLocationProvider(Self.sanFrancisco), isSimulated: true,
                                      defaults: UserDefaults(suiteName: "ExploreTests-\(UUID().uuidString)")!)
        #expect(model.coordinate == Self.sanFrancisco)
    }

    @Test func lateLocationFixRefitsToNearYouEvenAfterTheFirstSettles() async throws {
        let explore = try await makeExplore(lateFix: Self.sanFrancisco)
        #expect(!explore.hasLocation)
        explore.requestInitialCamera()
        guard case .fit(let all)? = explore.cameraRequest?.kind else { Issue.record("expected the first fit"); return }
        // MapKit settles on the first camera, then settles again on its own (a resize): not a user move.
        explore.cameraDidChange(to: all)
        explore.cameraDidChange(to: GeoRegion(center: all.center, latitudeDelta: all.latitudeDelta * 1.05,
                                              longitudeDelta: all.longitudeDelta * 1.05), byUser: true)
        let before = try #require(explore.cameraRequest)
        explore.start()
        for _ in 0..<200 where !explore.hasLocation { await Task.yield() }
        #expect(explore.hasLocation)
        explore.locationChanged()
        let after = try #require(explore.cameraRequest)
        #expect(after.id > before.id)
        guard case .fit(let region) = after.kind else { Issue.record("expected a fit"); return }
        #expect(region == MapCameraPolicy.fit(nearYouCoordinates(explore)))
        #expect(region.latitudeDelta < all.latitudeDelta || region.longitudeDelta < all.longitudeDelta)
    }

    @Test func lateLocationFixDoesNotRefitAfterTheUserMovedTheMap() async throws {
        let explore = try await makeExplore(lateFix: Self.sanFrancisco)
        explore.requestInitialCamera()
        guard case .fit(let all)? = explore.cameraRequest?.kind else { Issue.record("expected the first fit"); return }
        explore.cameraDidChange(to: all)
        explore.cameraDidChange(to: GeoRegion(center: Coordinate(latitude: 20, longitude: -100), latitudeDelta: 3, longitudeDelta: 3), byUser: true)
        let before = try #require(explore.cameraRequest)
        explore.start()
        for _ in 0..<200 where !explore.hasLocation { await Task.yield() }
        explore.locationChanged()
        #expect(explore.cameraRequest == before)
    }

    @Test func pinBudgetKeepsHierarchy() async throws {
        let explore = try await makeExplore()
        for spot in CuratedSpots.all { _ = await explore.app.forecasts.load(spot.coordinate) }
        explore.select("mesa-arch")
        let pins = explore.pins
        #expect(pins.count == explore.rows.count)
        #expect(pins.filter { $0.style == .selected }.map(\.id) == ["mesa-arch"])
        #expect(pins.filter { $0.style == .chip }.count == ExploreModel.pinBudget)
        #expect(pins.filter { $0.style == .dot }.count == pins.count - ExploreModel.pinBudget - 1)
        explore.hoveredID = pins.first { $0.style == .dot }?.id
        #expect(explore.pins.filter { $0.style == .chip }.count == ExploreModel.pinBudget + 1)
    }

    @Test func addSpotModeDropsAPinAndSelectsTheNewSpot() async throws {
        let explore = try await makeExplore()
        explore.dropPin(at: Coordinate(latitude: 1, longitude: 1))
        #expect(explore.draftCoordinate == nil)
        explore.beginAddingSpot()
        explore.dropPin(at: Coordinate(latitude: 38.5, longitude: -109.5))
        #expect(explore.draftCoordinate?.latitude == 38.5)
        let record = explore.app.store.createUserSpot(name: "New", coordinate: Coordinate(latitude: 38.5, longitude: -109.5),
                                                      timeZoneIdentifier: "America/Denver")
        explore.didCreate(record.spot)
        #expect(explore.isAddingSpot == false)
        #expect(explore.draftCoordinate == nil)
        #expect(explore.selectedID == record.spot.id)
    }

    @Test func leavingAddSpotModeDiscardsTheDraft() async throws {
        let explore = try await makeExplore()
        explore.beginAddingSpot()
        explore.dropPin(at: Coordinate(latitude: 38.5, longitude: -109.5))
        explore.isAddingSpot = false
        #expect(explore.draftCoordinate == nil)
    }

    @Test func dayNavigation() async throws {
        let explore = try await makeExplore()
        explore.goToToday()
        #expect(explore.isToday)
        explore.shiftDay(by: 1)
        #expect(!explore.isToday)
        explore.shiftDay(by: -1)
        #expect(explore.isToday)
    }

    // MARK: Row expansion

    @Test func clickExpandsAndSelects() async throws {
        let explore = try await makeExplore()
        explore.rowClicked("mesa-arch")
        #expect(explore.selectedID == "mesa-arch")
        #expect(explore.expandedID == "mesa-arch")
        #expect(explore.scrollRequest == nil)
    }

    @Test func clickingAgainCollapsesButKeepsSelection() async throws {
        let explore = try await makeExplore()
        explore.rowClicked("mesa-arch")
        explore.rowClicked("mesa-arch")
        #expect(explore.expandedID == nil)
        #expect(explore.selectedID == "mesa-arch")
    }

    @Test func clickingAnotherRowMovesTheExpansion() async throws {
        let explore = try await makeExplore()
        let other = try #require(CuratedSpots.all.first { $0.id != "mesa-arch" }).id
        explore.rowClicked("mesa-arch")
        explore.rowClicked(other)
        #expect(explore.expandedID == other)
        #expect(explore.selectedID == other)
    }

    /// The List's selection binding and the tap gesture can arrive in either order.
    @Test func bindingAndTapInEitherOrderEndExpanded() async throws {
        let other = try #require(CuratedSpots.all.first { $0.id != "mesa-arch" }).id
        // Binding first, then tap.
        let a = try await makeExplore()
        a.rowClicked("mesa-arch")
        a.select(other, from: .list)
        a.rowClicked(other)
        #expect(a.expandedID == other && a.selectedID == other)
        // Tap first, then binding.
        let b = try await makeExplore()
        b.rowClicked("mesa-arch")
        b.rowClicked(other)
        b.select(other, from: .list)
        #expect(b.expandedID == other && b.selectedID == other)
        // Click on the selected, expanded row: only the tap arrives.
        b.rowClicked(other)
        #expect(b.expandedID == nil && b.selectedID == other)
    }

    @Test func keyboardSelectionOfAnotherRowCollapses() async throws {
        let explore = try await makeExplore()
        let other = try #require(CuratedSpots.all.first { $0.id != "mesa-arch" }).id
        explore.rowClicked("mesa-arch")
        explore.select(other, from: .list)
        #expect(explore.expandedID == nil)
        #expect(explore.selectedID == other)
    }

    @Test func toggleOnTheSelectedRow() async throws {
        let explore = try await makeExplore()
        explore.toggleExpansion()
        #expect(explore.expandedID == nil)
        explore.select("mesa-arch", from: .list)
        explore.toggleExpansion()
        #expect(explore.expandedID == "mesa-arch")
        explore.toggleExpansion()
        #expect(explore.expandedID == nil)
    }

    @Test func mapSelectionDoesNotExpandAndCollapsesAnother() async throws {
        let explore = try await makeExplore()
        let other = try #require(CuratedSpots.all.first { $0.id != "mesa-arch" }).id
        explore.select(other, from: .map)
        #expect(explore.expandedID == nil)
        explore.rowClicked("mesa-arch")
        explore.select(other, from: .map)
        #expect(explore.expandedID == nil)
        #expect(explore.selectedID == other)
    }

    @Test func expansionClearsWhenTheRowIsFilteredOut() async throws {
        let explore = try await makeExplore()
        explore.rowClicked("mesa-arch")
        explore.filters.sources = [.yours]
        #expect(explore.expandedID == nil)
        #expect(explore.selectedID == nil)
    }

    @Test func listSelectionMakesNoScrollRequest() async throws {
        let explore = try await makeExplore()
        explore.select("mesa-arch", from: .list)
        explore.toggleExpansion()
        #expect(explore.scrollRequest == nil)
    }
}

// MARK: - Near you

private let sanFrancisco = Coordinate(latitude: 37.77, longitude: -122.42)
private let moab = Coordinate(latitude: 38.57, longitude: -109.55)

private func miles(_ a: Coordinate, _ b: Coordinate) -> Double { a.distance(to: b) / 1609.344 }

@MainActor
@Suite struct ExploreNearYouTests {
    private func kinds(_ explore: ExploreModel) -> [ExploreSectionKind] { explore.sections.map(\.kind) }
    private func ids(_ explore: ExploreModel, _ kind: ExploreSectionKind) -> [String] {
        explore.sections.first { $0.kind == kind }?.rows.map(\.id) ?? []
    }

    @Test func withoutALocationThereIsOneSpotsSection() async throws {
        let explore = try await makeExplore()
        #expect(kinds(explore) == [.spots])
        #expect(explore.rows.count == CuratedSpots.all.count)
        #expect(explore.sort == .bestLight)
        #expect(explore.rows.allSatisfy { $0.distanceMeters == nil })
    }

    @Test func aFixSplitsNearPopularAndMore() async throws {
        let explore = try await makeExplore(at: moab)
        #expect(kinds(explore) == [.nearYou, .popular, .morePlaces])
        let radius = Double(explore.radiusMiles)
        let all = CuratedSpots.all
        let near = Set(all.filter { miles(moab, $0.coordinate) <= radius }.map(\.id))
        let far = all.filter { miles(moab, $0.coordinate) > radius }
        #expect(Set(ids(explore, .nearYou)) == near)
        #expect(Set(ids(explore, .popular)) == Set(far.filter { $0.popularity >= ExploreModel.popularThreshold }.map(\.id)))
        #expect(Set(ids(explore, .morePlaces)) == Set(far.filter { $0.popularity < ExploreModel.popularThreshold }.map(\.id)))
        #expect(explore.rows.count == all.count)
        // Every row shows its distance from you.
        #expect(explore.rows.allSatisfy { $0.distanceMeters != nil })
    }

    @Test func nearIsSortedByDistanceByDefaultAndPopularByPopularity() async throws {
        let explore = try await makeExplore(at: sanFrancisco)
        #expect(explore.sort == .distance)
        let near = explore.sections.first { $0.kind == .nearYou }?.rows ?? []
        #expect(!near.isEmpty)
        let d = near.compactMap(\.distanceMeters)
        #expect(d == d.sorted())
        let pops = (explore.sections.first { $0.kind == .popular }?.rows ?? []).map(\.spot.popularity)
        #expect(pops == pops.sorted(by: >))
        #expect(pops.allSatisfy { $0 >= ExploreModel.popularThreshold })
        // Choosing a sort sticks, and a location does not override it.
        explore.sort = .name
        #expect(explore.sort == .name)
    }

    @Test func theRadiusBoundaryIsInclusive() async throws {
        let target = try #require(CuratedSpots.all.filter { miles(moab, $0.coordinate) > 50 }.min { miles(moab, $0.coordinate) < miles(moab, $1.coordinate) })
        let d = miles(moab, target.coordinate)
        let inside = try await makeExplore(at: moab, radius: Int(d.rounded(.up)))
        #expect(ids(inside, .nearYou).contains(target.id))
        let outside = try await makeExplore(at: moab, radius: Int(d.rounded(.down)))
        #expect(!ids(outside, .nearYou).contains(target.id))
    }

    @Test func theRadiusChangeRegroupsTheList() async throws {
        let explore = try await makeExplore(at: moab, radius: 100)
        let small = ids(explore, .nearYou).count
        explore.app.location.radiusMiles = 500
        #expect(ids(explore, .nearYou).count > small)
        #expect(explore.radiusMiles == 500)
        let popularAfter = ids(explore, .popular)
        #expect(popularAfter.allSatisfy { id in (explore.row(id: id)?.distanceMeters ?? 0) > 500 * 1609.344 })
    }

    @Test func popularNeedsACuratedSpotAtTheThreshold() async throws {
        let explore = try await makeExplore(at: sanFrancisco, radius: 100)
        let popular = ids(explore, .popular).compactMap { CuratedSpots.spot(id: $0) }
        #expect(!popular.isEmpty)
        #expect(popular.allSatisfy { $0.popularity >= 80 })
        let more = ids(explore, .morePlaces).compactMap { CuratedSpots.spot(id: $0) }
        #expect(more.allSatisfy { $0.popularity < 80 })
    }

    @Test func yourOwnSpotsNearYouAreInNearYou() async throws {
        let explore = try await makeExplore(at: moab)
        let record = explore.app.store.createUserSpot(name: "My Pull-off", coordinate: Coordinate(latitude: 38.6, longitude: -109.6),
                                                      timeZoneIdentifier: "America/Denver")
        #expect(ids(explore, .nearYou).contains(record.spot.id))
        // A faraway one of yours is listed under More Places, never Popular.
        let far = explore.app.store.createUserSpot(name: "Far Pull-off", coordinate: Coordinate(latitude: 47, longitude: -122),
                                                   timeZoneIdentifier: "America/Los_Angeles")
        #expect(ids(explore, .morePlaces).contains(far.spot.id))
    }

    @Test func filtersAndSearchApplyToEverySection() async throws {
        let explore = try await makeExplore(at: moab)
        explore.filters.categories = [.desert]
        let desert = Set(CuratedSpots.all.filter { $0.category == .desert }.map(\.id))
        #expect(Set(explore.rows.map(\.id)) == desert)
        #expect(explore.sections.flatMap(\.rows).allSatisfy { $0.spot.category == .desert })
        explore.clearFilters()
        explore.query = "mesa arch"
        #expect(explore.rows.map(\.id).contains("mesa-arch"))
        #expect(explore.rows.count < CuratedSpots.all.count)
    }

    @Test func moreOpensForASelectionOrASearch() async throws {
        let explore = try await makeExplore(at: sanFrancisco, radius: 100)
        let hidden = try #require(ids(explore, .morePlaces).first)
        #expect(!explore.isMorePlacesOpen)
        explore.select(hidden, from: .map)
        #expect(explore.isMorePlacesOpen)
        explore.setMorePlacesOpen(false)
        #expect(!explore.isMorePlacesOpen)
        explore.query = "arch"
        #expect(explore.isMorePlacesOpen)
    }

    @Test func theFitFramesNearYouAndNeverTheWholeWorld() async throws {
        let explore = try await makeExplore(at: moab, radius: 300)
        let near = ids(explore, .nearYou).compactMap { explore.row(id: $0)?.spot.coordinate }
        #expect(Set(explore.fitCoordinates.map(\.latitude)) == Set(near.map(\.latitude)))
        explore.requestInitialCamera()
        guard case .fit(let region)? = explore.cameraRequest?.kind else { Issue.record("expected a fit"); return }
        #expect(region.latitudeDelta <= MapCameraPolicy.maxAutomaticSpan)
        for c in near { #expect(region.contains(c)) }
    }

    @Test func aMovedMapIsNotRefitAndTheSettledCameraIsSaved() async throws {
        let explore = try await makeExplore()
        explore.requestInitialCamera()
        guard case .fit(let fit)? = explore.cameraRequest?.kind else { Issue.record("expected a fit"); return }
        explore.cameraDidChange(to: fit)
        explore.filters.categories = [.desert]
        let refit = try #require(explore.cameraRequest)
        guard case .fit = refit.kind else { Issue.record("expected a refit"); return }
        // The user zooms in: later changes leave the camera alone.
        explore.cameraDidChange(to: GeoRegion(center: Coordinate(latitude: 38, longitude: -110), latitudeDelta: 0.5, longitudeDelta: 0.5), byUser: true)
        explore.filters.categories = [.waterfall]
        #expect(explore.cameraRequest == refit)
    }

    @Test func aSettleWeCausedOrMapKitsInitialCameraIsNotAUserMove() async throws {
        let explore = try await makeExplore()
        // MapKit's initial camera, before any request: not saved, not a user move.
        explore.cameraDidChange(to: GeoRegion(center: Coordinate(latitude: 40, longitude: -116), latitudeDelta: 121, longitudeDelta: 122))
        #expect(explore.cameraPolicy.savedRegion == nil)
        explore.requestInitialCamera()
        guard case .fit(let fit)? = explore.cameraRequest?.kind else { Issue.record("expected a fit"); return }
        // The fit settles at a different, aspect-adjusted region: still ours.
        explore.cameraDidChange(to: GeoRegion(center: fit.center, latitudeDelta: fit.latitudeDelta * 1.1, longitudeDelta: fit.longitudeDelta * 1.1))
        #expect(!explore.cameraPolicy.userMovedSinceFit)
        #expect(explore.cameraPolicy.savedRegion?.latitudeDelta == fit.latitudeDelta * 1.1)
    }

    @Test func aWideNonUserSettleAfterAFitIsNotSavedAndTheFitIsRequestedAgain() async throws {
        let explore = try await makeExplore()
        explore.requestInitialCamera()
        guard case .fit(let fit)? = explore.cameraRequest?.kind, let first = explore.cameraRequest else { Issue.record("expected a fit"); return }
        // MapKit's own wide camera, as when the pane had no size yet.
        explore.cameraDidChange(to: GeoRegion(center: fit.center, latitudeDelta: 122, longitudeDelta: 100))
        #expect(explore.cameraPolicy.savedRegion == nil)
        #expect(!explore.cameraPolicy.userMovedSinceFit)
        let again = try #require(explore.cameraRequest)
        #expect(again.id > first.id)
        guard case .fit(let reapplied) = again.kind else { Issue.record("expected a fit"); return }
        #expect(reapplied == fit)
    }

    @Test func aUserSettleIsSavedAndMarksMoved() async throws {
        let explore = try await makeExplore()
        explore.requestInitialCamera()
        guard case .fit(let fit)? = explore.cameraRequest?.kind else { Issue.record("expected a fit"); return }
        explore.cameraDidChange(to: fit)
        let user = GeoRegion(center: fit.center, latitudeDelta: 90, longitudeDelta: 100)
        explore.cameraDidChange(to: user, byUser: true)
        #expect(explore.cameraPolicy.savedRegion == user)
        #expect(explore.cameraPolicy.userMovedSinceFit)
    }

    private static let oregonCoast = Coordinate(latitude: 45.88, longitude: -123.96)
    private static let bayArea = GeoRegion(center: Coordinate(latitude: 37.8, longitude: -122.3), latitudeDelta: 1.5, longitudeDelta: 1.5)

    @Test func aSelectionMadeBeforeTheMapExistsIsInTheInitialRegion() async throws {
        let explore = try await makeExplore(at: Self.oregonCoast)
        let before = try #require(explore.initialCameraRegion)
        // A spot just outside the fit: pick the farthest listed row from the region's centre.
        let far = try #require(explore.rows.max { lhs, rhs in
            abs(lhs.spot.coordinate.latitude - before.center.latitude) < abs(rhs.spot.coordinate.latitude - before.center.latitude)
        })
        explore.select(far.id, from: .list)
        let after = try #require(explore.initialCameraRegion)
        #expect(after.contains(far.spot.coordinate))
        #expect(after.latitudeDelta == before.latitudeDelta && after.longitudeDelta == before.longitudeDelta)
        explore.requestInitialCamera()
        guard case .fit(let requested)? = explore.cameraRequest?.kind else { Issue.record("expected a fit"); return }
        #expect(requested == after)
    }

    @Test func aStaleAutomaticSavedCameraGivesWayToTheNearYouFit() async throws {
        let explore = try await makeExplore(at: Self.oregonCoast, savedCamera: (Self.bayArea, false))
        let near = explore.sections.first { $0.kind == .nearYou }?.rows.map(\.spot.coordinate) ?? []
        #expect(!near.isEmpty)
        #expect(explore.initialCameraRegion == MapCameraPolicy.fit(near))
    }

    @Test func aUserChosenSavedCameraIsKept() async throws {
        let explore = try await makeExplore(at: Self.oregonCoast, savedCamera: (Self.bayArea, true))
        #expect(explore.initialCameraRegion == Self.bayArea)
    }
}
