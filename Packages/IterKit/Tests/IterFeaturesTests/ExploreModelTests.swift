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

@MainActor
private func makeExplore(search: FakeSearch = FakeSearch(), weatherDown: Bool = false) throws -> ExploreModel {
    let store = IterStore(container: try IterSchema.makeContainer(inMemory: true))
    let clock: @Sendable () -> Date = { fixedNow }
    let sample = CachedWeatherService(wrapping: SampleWeatherService(now: clock))
    let defaults = UserDefaults(suiteName: "ExploreTests-\(UUID().uuidString)")!
    let app = AppModel(store: store, weather: weatherDown ? DownWeather() : sample, search: search, geocoder: NoGeocoder(),
                       drives: NoDrives(), scout: nil, sampleWeather: sample, defaults: defaults, now: { fixedNow })
    let explore = ExploreModel(app: app, searchDebounce: .zero)
    explore.day = LocalDay(year: 2026, month: 10, day: 6)
    return explore
}

private func place(_ id: String, _ name: String, lat: Double = 38.7, lon: Double = -109.6) -> PlaceResult {
    PlaceResult(id: id, name: name, locality: "Moab, UT", coordinate: Coordinate(latitude: lat, longitude: lon),
                timeZoneIdentifier: "America/Denver", pointOfInterestCategory: nil)
}

@MainActor
@Suite struct ExploreModelTests {
    @Test func listsAllCuratedSpotsWithAHeadlineWindow() async throws {
        let explore = try makeExplore()
        #expect(explore.rows.count == CuratedSpots.all.count)
        _ = await explore.app.forecasts.load(CuratedSpots.all[0].coordinate)
        let row = try #require(explore.row(id: CuratedSpots.all[0].id))
        #expect(row.window != nil)
        #expect(row.source == .curated)
    }

    @Test func textFilterMatchesNameLocalityAndTagsIgnoringCase() throws {
        let explore = try makeExplore()
        explore.query = "mesa arch"
        #expect(explore.rows.map(\.id).contains("mesa-arch"))
        #expect(explore.rows.allSatisfy { $0.spot.name.localizedCaseInsensitiveContains("mesa") || $0.spot.locality.localizedCaseInsensitiveContains("mesa") || $0.spot.tags.contains { $0.localizedCaseInsensitiveContains("mesa") } })
        explore.query = "MESA ARCH"
        #expect(explore.row(id: "mesa-arch") != nil)
        explore.query = "zzzzqq"
        #expect(explore.rows.isEmpty)
    }

    @Test func categoryAndSourceFilters() throws {
        let explore = try makeExplore()
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

    @Test func bestLightFilterKeepsSpotsKnownForIt() throws {
        let explore = try makeExplore()
        explore.filters.bestLight = [.night]
        #expect(!explore.rows.isEmpty)
        #expect(explore.rows.allSatisfy { $0.spot.bestLight.contains(.night) })
    }

    @Test func yourSpotsAreListedAndSourceFiltered() throws {
        let explore = try makeExplore()
        let record = explore.app.store.createUserSpot(name: "My Pull-off", coordinate: Coordinate(latitude: 38.5, longitude: -109.5),
                                                      timeZoneIdentifier: "America/Denver")
        #expect(explore.row(id: record.spot.id)?.source == .yours)
        explore.filters.sources = [.yours]
        #expect(explore.rows.map(\.id) == [record.spot.id])
    }

    @Test func bestLightSortPutsScoredFirstAndUnscoredLast() async throws {
        let explore = try makeExplore()
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

    @Test func nameAndPopularitySort() throws {
        let explore = try makeExplore()
        explore.sort = .name
        let names = explore.rows.map(\.spot.name)
        #expect(names == names.sorted { $0.localizedStandardCompare($1) == .orderedAscending })
        explore.sort = .popularity
        let pops = explore.rows.map(\.spot.popularity)
        #expect(pops == pops.sorted(by: >))
    }

    @Test func distanceSortUsesTheVisibleCentre() throws {
        let explore = try makeExplore()
        let tunnelView = try #require(CuratedSpots.spot(id: "tunnel-view"))
        explore.cameraDidChange(to: GeoRegion(center: tunnelView.coordinate, latitudeDelta: 1, longitudeDelta: 1))
        explore.sort = .distance
        #expect(explore.rows.first?.id == "tunnel-view")
        let distances = explore.rows.compactMap(\.distanceMeters)
        #expect(distances == distances.sorted())
    }

    @Test func noForecastRowsCarryTheReasonAndTheNoticeIsOneLine() async throws {
        let explore = try makeExplore(weatherDown: true)
        for spot in CuratedSpots.all { _ = await explore.app.forecasts.load(spot.coordinate) }
        #expect(explore.rows.allSatisfy { $0.score == nil })
        // A sunrise window earlier today is honestly "passed"; everything else names the missing service.
        #expect(explore.rows.allSatisfy { $0.unavailableReason == .weatherServiceNotEnabled || $0.unavailableReason == .inThePast })
        #expect(explore.forecastNotice == .weatherServiceNotEnabled)
        #expect(!explore.isLoadingForecasts)
    }

    @Test func searchTransitionsIdleSearchingFinished() async throws {
        let explore = try makeExplore(search: FakeSearch(results: [place("am1", "Delicate Arch Viewpoint"), place("am2", "Park Avenue")]))
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
        let explore = try makeExplore(search: FakeSearch(results: []))
        explore.query = "nowhere at all"
        explore.submitSearch()
        await explore.searchTask?.value
        #expect(explore.searchState == .finished(query: "nowhere at all", count: 0))
    }

    @Test func searchFailureIsReportedAndRetryable() async throws {
        let explore = try makeExplore(search: FakeSearch(fails: true))
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
        let explore = try makeExplore(search: FakeSearch(results: [place("am1", "Late Result")]))
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

    @Test func appleMapsResultsWithoutZoneBorrowTheNearestCuratedZone() throws {
        let explore = try makeExplore()
        var p = place("x", "Somewhere", lat: 36.1, lon: -112.1)
        p.timeZoneIdentifier = nil
        #expect(explore.spot(from: p).timeZoneIdentifier == CuratedSpots.all.min { $0.coordinate.distance(to: p.coordinate) < $1.coordinate.distance(to: p.coordinate) }?.timeZoneIdentifier)
    }

    @Test func selectionFromTheListPansOnlyWhenOutOfView() throws {
        let explore = try makeExplore()
        let mesa = try #require(CuratedSpots.spot(id: "mesa-arch"))
        explore.cameraDidChange(to: GeoRegion(center: mesa.coordinate, latitudeDelta: 2, longitudeDelta: 2))
        explore.select("mesa-arch", from: .list)
        #expect(explore.selectedID == "mesa-arch")
        #expect(explore.cameraRequest == nil || explore.cameraRequest?.kind != .center(mesa.coordinate))
        let far = try #require(CuratedSpots.spot(id: "tunnel-view"))
        explore.select("tunnel-view", from: .list)
        #expect(explore.cameraRequest?.kind == .center(far.coordinate))
    }

    @Test func selectionFromTheMapScrollsTheListAndDoesNotPan() throws {
        let explore = try makeExplore()
        explore.select("mesa-arch", from: .map)
        #expect(explore.scrollRequest?.target == "mesa-arch")
        #expect(explore.cameraRequest == nil)
    }

    @Test func filteringOutTheSelectionClearsIt() throws {
        let explore = try makeExplore()
        explore.select("mesa-arch")
        explore.filters.categories = [.waterfall]
        #expect(explore.selectedID == nil)
    }

    @Test func fitIsRequestedWhenTheResultSetChanges() throws {
        let explore = try makeExplore()
        explore.requestFit()
        let first = try #require(explore.cameraRequest)
        explore.filters.categories = [.desert]
        let second = try #require(explore.cameraRequest)
        #expect(second.id > first.id)
        guard case .fit(let region) = second.kind else { Issue.record("expected a fit"); return }
        for spot in CuratedSpots.all where spot.category == .desert { #expect(region.contains(spot.coordinate)) }
    }

    @Test func pinBudgetKeepsHierarchy() async throws {
        let explore = try makeExplore()
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

    @Test func addSpotModeDropsAPinAndSelectsTheNewSpot() throws {
        let explore = try makeExplore()
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

    @Test func leavingAddSpotModeDiscardsTheDraft() throws {
        let explore = try makeExplore()
        explore.beginAddingSpot()
        explore.dropPin(at: Coordinate(latitude: 38.5, longitude: -109.5))
        explore.isAddingSpot = false
        #expect(explore.draftCoordinate == nil)
    }

    @Test func dayNavigation() throws {
        let explore = try makeExplore()
        explore.goToToday()
        #expect(explore.isToday)
        explore.shiftDay(by: 1)
        #expect(!explore.isToday)
        explore.shiftDay(by: -1)
        #expect(explore.isToday)
    }
}
