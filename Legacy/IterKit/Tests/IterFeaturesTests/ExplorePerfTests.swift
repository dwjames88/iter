import Foundation
import Testing
import IterCore
import Synchronization
import IterAstro
import IterData
import IterServices
@testable import IterFeatures

private let denver = TimeZone(identifier: "America/Denver")!
private let fixedNow = LocalDay(year: 2026, month: 10, day: 6).at(hour: 10, in: denver)

private struct StubSearch: PlaceSearching {
    var results: [PlaceResult] = []
    func search(_ query: String, near region: GeoRegion?) async throws -> [PlaceResult] { results }
    func pointsOfInterest(near center: Coordinate, radiusMeters: Double, categories: [String]) async throws -> [PlaceResult] { [] }
}

private struct StubDrives: DriveTimeProviding {
    func drive(from a: Coordinate, to b: Coordinate) async throws -> DriveLeg { DriveLeg.estimate(from: a, to: b) }
}

private struct StubGeocoder: Geocoding {
    func reverseGeocode(_ coordinate: Coordinate) async throws -> PlaceResult { throw MapServiceError.noResult }
    func geocode(_ query: String) async throws -> [PlaceResult] { [] }
}

private let sanFrancisco = Coordinate(latitude: 37.77, longitude: -122.42)
private let moab = Coordinate(latitude: 38.57, longitude: -109.55)
private let iceland = Coordinate(latitude: 64.14, longitude: -21.9)

@MainActor
private func makeExplore(results: [PlaceResult] = [], at fix: Coordinate? = nil,
                         savedCamera: (region: GeoRegion, byUser: Bool)? = nil) async throws -> ExploreModel {
    let store = IterStore(container: try IterSchema.makeContainer(inMemory: true))
    let clock: @Sendable () -> Date = { fixedNow }
    let sample = CachedWeatherService(wrapping: SampleWeatherService(now: clock))
    let defaults = UserDefaults(suiteName: "ExplorePerfTests-\(UUID().uuidString)")!
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
        ?? UserLocationModel(defaults: defaults)
    let app = AppModel(store: store, weather: sample, search: StubSearch(results: results), geocoder: StubGeocoder(),
                       drives: StubDrives(), scout: nil, location: location, sampleWeather: sample, defaults: defaults,
                       now: { fixedNow })
    let explore = ExploreModel(app: app, searchDebounce: .zero, defaults: defaults)
    explore.scoringDelay = .milliseconds(1)
    return explore
}

private func place(_ id: String, _ name: String, at c: Coordinate) -> PlaceResult {
    PlaceResult(id: id, name: name, locality: "Reykjavik", coordinate: c, timeZoneIdentifier: "Atlantic/Reykjavik",
                pointOfInterestCategory: nil)
}

private let moabCamera = GeoRegion(center: moab, latitudeDelta: 2, longitudeDelta: 2)

// MARK: - A search result is brought into view (TESTING.md known gap 11)

@MainActor
@Suite struct ExploreSearchCameraTests {
    @Test func aResultOffScreenIsFramedAfterTheMapWasMovedByHand() async throws {
        let explore = try await makeExplore(results: [place("is1", "Skogafoss", at: iceland)], savedCamera: (moabCamera, true))
        explore.requestInitialCamera()
        explore.cameraDidChange(to: moabCamera)
        let before = explore.cameraRequest
        explore.query = "Skogafoss"
        explore.searchAppleMaps()
        await explore.searchTask?.value
        let request = try #require(explore.cameraRequest)
        #expect(request.id != before?.id)
        guard case .fit(let region) = request.kind else { Issue.record("expected a fit"); return }
        #expect(region.contains(iceland))
        // A programmatic request: the settle that follows is not a user move.
        #expect(explore.cameraPolicy.intendedRegion == region)
        #expect(!explore.cameraPolicy.userMovedSinceFit)
    }

    @Test func aResultFarFromNearYouIsFramedEvenWhenTheMapWasNeverMoved() async throws {
        let explore = try await makeExplore(results: [place("is1", "Skogafoss", at: iceland)], at: moab)
        explore.requestInitialCamera()
        guard case .fit(let initial)? = explore.cameraRequest?.kind else { Issue.record("expected a fit"); return }
        explore.cameraDidChange(to: initial)
        explore.query = "Skogafoss"
        explore.searchAppleMaps()
        await explore.searchTask?.value
        guard case .fit(let region)? = explore.cameraRequest?.kind else { Issue.record("expected a fit"); return }
        // Before the fix the list-wide refit weighed the many Near You spots and left Iceland off the map.
        #expect(region.contains(iceland))
    }

    @Test func resultsAlreadyOnTheMapDoNotMoveIt() async throws {
        let near = place("am1", "Delicate Arch Viewpoint", at: Coordinate(latitude: 38.74, longitude: -109.5))
        let explore = try await makeExplore(results: [near], savedCamera: (moabCamera, true))
        explore.requestInitialCamera()
        explore.cameraDidChange(to: moabCamera)
        let before = explore.cameraRequest
        explore.query = "Delicate Arch"
        explore.searchAppleMaps()
        await explore.searchTask?.value
        #expect(explore.cameraRequest == before)
    }

    @Test func anEmptySearchLeavesTheCameraAlone() async throws {
        let explore = try await makeExplore(results: [], savedCamera: (moabCamera, true))
        explore.requestInitialCamera()
        explore.cameraDidChange(to: moabCamera)
        let before = explore.cameraRequest
        explore.query = "nowhere"
        explore.searchAppleMaps()
        await explore.searchTask?.value
        #expect(explore.cameraRequest == before)
    }
}

// MARK: - Near You distance maths

@MainActor
@Suite struct ExploreDistanceTests {
    private func nearIDs(_ explore: ExploreModel) -> Set<String> {
        Set(explore.sections.first { $0.kind == .nearYou }?.rows.map(\.id) ?? [])
    }

    /// A point `miles` due north of `origin` (a pure latitude step is exact on the haversine sphere).
    private func north(of origin: Coordinate, miles: Double) -> Coordinate {
        let degrees = miles * 1609.344 / Coordinate.earthRadiusMeters * 180 / .pi
        return Coordinate(latitude: origin.latitude + degrees, longitude: origin.longitude)
    }

    @Test func aSpotJustInsideAndJustOutsideTheRadius() async throws {
        let explore = try await makeExplore(at: moab)
        let radius = Double(explore.radiusMiles)
        let inside = explore.app.store.createUserSpot(name: "Inside", coordinate: north(of: moab, miles: radius - 0.01),
                                                      timeZoneIdentifier: "America/Denver")
        let outside = explore.app.store.createUserSpot(name: "Outside", coordinate: north(of: moab, miles: radius + 0.01),
                                                       timeZoneIdentifier: "America/Denver")
        #expect(nearIDs(explore).contains(inside.spot.id))
        #expect(!nearIDs(explore).contains(outside.spot.id))
        let more = explore.sections.first { $0.kind == .morePlaces }?.rows.map(\.id) ?? []
        #expect(more.contains(outside.spot.id))
    }

    @Test func theRadiusChoicesAreTheDocumentedFourWithThreeHundredDefault() {
        #expect(UserLocationModel.radiusChoices == [100, 200, 300, 500])
        #expect(UserLocationModel.defaultRadiusMiles == 300)
    }

    @Test func distanceIsGreatCircleAcrossTheAntimeridian() {
        let a = Coordinate(latitude: 0, longitude: 179.9)
        let b = Coordinate(latitude: 0, longitude: -179.9)
        let miles = a.distance(to: b) / 1609.344
        // 0.2 degrees of longitude on the equator: about 13.8 miles, not the 24,000 of the raw difference.
        #expect(abs(miles - 13.8) < 0.2)
    }

    @Test func aSpotAcrossTheAntimeridianIsNear() async throws {
        let user = Coordinate(latitude: -17.7, longitude: 179.9)
        let explore = try await makeExplore(at: user)
        let across = explore.app.store.createUserSpot(name: "Across the line", coordinate: Coordinate(latitude: -17.7, longitude: -179.9),
                                                      timeZoneIdentifier: "Pacific/Fiji")
        #expect(nearIDs(explore).contains(across.spot.id))
        let row = try #require(explore.row(id: across.spot.id))
        #expect((row.distanceMeters ?? .infinity) < 30_000)
    }

    @Test func withoutALocationNothingIsNearOrMore() async throws {
        let explore = try await makeExplore()
        #expect(explore.sections.map(\.kind) == [.spots])
        #expect(explore.rows.allSatisfy { $0.distanceMeters == nil })
    }

    @Test func nearYouIsSortedNearestFirstAndSectionCountsAddUp() async throws {
        let explore = try await makeExplore(at: sanFrancisco)
        let sections = explore.sections
        #expect(sections.map(\.kind) == [.nearYou, .popular, .morePlaces])
        #expect(sections.reduce(0) { $0 + $1.rows.count } == CuratedSpots.all.count)
        let near = try #require(sections.first { $0.kind == .nearYou }).rows.compactMap(\.distanceMeters)
        #expect(near == near.sorted())
        // More Places stays collapsed until opened, a search opens it, and the user can close it again.
        #expect(!explore.isMorePlacesOpen)
        explore.query = "a"
        #expect(explore.isMorePlacesOpen)
    }
}

// MARK: - What a change rebuilds

@MainActor
@Suite struct ExploreRebuildTests {
    @Test func hoveringRebuildsTheMapItemsOnceAndNeverTheRows() async throws {
        let explore = try await makeExplore(at: sanFrancisco)
        explore.setMapViewport(CGSize(width: 900, height: 700))
        explore.cameraDidChange(to: GeoRegion(center: sanFrancisco, latitudeDelta: 10, longitudeDelta: 12))
        _ = explore.mapItems
        let rows = explore.derivedBuilds, maps = explore.mapBuilds
        let id = try #require(explore.rows.first?.id)
        explore.hoveredID = id
        _ = explore.mapItems
        _ = explore.mapItems
        explore.hoveredID = nil
        _ = explore.mapItems
        #expect(explore.derivedBuilds == rows)
        #expect(explore.mapBuilds == maps + 2)
    }

    @Test func readingRowsTwiceBuildsThemOnce() async throws {
        let explore = try await makeExplore(at: sanFrancisco)
        _ = explore.rows
        let before = explore.derivedBuilds
        for _ in 0..<20 { _ = explore.rows; _ = explore.sections; _ = explore.row(id: "mesa-arch"); _ = explore.panelPosition }
        #expect(explore.derivedBuilds == before)
    }

    @Test func steppingThroughTheListBuildsNoRowsAndOneCameraRequestPerStep() async throws {
        let explore = try await makeExplore(at: sanFrancisco)
        explore.cameraDidChange(to: GeoRegion(center: sanFrancisco, latitudeDelta: 10, longitudeDelta: 12))
        await explore.waitForScoring()
        let first = try #require(explore.rows.first?.id)
        explore.select(first, from: .list)
        let before = explore.derivedBuilds
        var ids = Set<Int>()
        for _ in 0..<10 {
            explore.selectNext()
            if let id = explore.cameraRequest?.id { ids.insert(id) }
        }
        #expect(explore.derivedBuilds == before)
        #expect(ids.count == 10)
    }

    @Test func aFullForecastFanOutRebuildsRowsAtMostOncePerArrivalAndScoresInFewBatches() async throws {
        let explore = try await makeExplore(at: sanFrancisco)
        explore.cameraDidChange(to: GeoRegion(center: sanFrancisco, latitudeDelta: 10, longitudeDelta: 12))
        _ = explore.rows
        let rowsBefore = explore.derivedBuilds, batchesBefore = explore.scoreBatches
        explore.requestForecasts()
        for spot in CuratedSpots.all { _ = await explore.app.forecasts.load(spot.coordinate) }
        await explore.waitForScoring()
        print("fan-out: rows rebuilt \(explore.derivedBuilds - rowsBefore), score batches \(explore.scoreBatches - batchesBefore), spots \(CuratedSpots.all.count)")
        #expect(explore.rows.allSatisfy { $0.score != nil })
    }
}

// MARK: - The panel's model keeps its work when another spot's forecast arrives

private final class Counter: Sendable {
    private let count = Mutex(0)
    func bump() { count.withLock { $0 += 1 } }
    var value: Int { count.withLock { $0 } }
}

private struct CountingEphemeris: Ephemeris {
    let base = Astronomy()
    let positions: Counter
    func sunEvents(on day: LocalDay, at coordinate: Coordinate, in timeZone: TimeZone) -> SunEvents { base.sunEvents(on: day, at: coordinate, in: timeZone) }
    func sunPosition(at date: Date, coordinate: Coordinate) -> SkyPosition { positions.bump(); return base.sunPosition(at: date, coordinate: coordinate) }
    func moonPosition(at date: Date, coordinate: Coordinate) -> SkyPosition { positions.bump(); return base.moonPosition(at: date, coordinate: coordinate) }
    func moonPhase(at date: Date) -> MoonPhase { base.moonPhase(at: date) }
    func moonEvents(on day: LocalDay, at coordinate: Coordinate, in timeZone: TimeZone) -> MoonEvents { base.moonEvents(on: day, at: coordinate, in: timeZone) }
}

@MainActor
@Suite struct SpotModelCacheTests {
    @Test func anotherSpotsForecastKeepsThePathsAndTheRose() async throws {
        let store = IterStore(container: try IterSchema.makeContainer(inMemory: true))
        let clock: @Sendable () -> Date = { fixedNow }
        let sample = CachedWeatherService(wrapping: SampleWeatherService(now: clock))
        let positions = Counter()
        let app = AppModel(store: store, weather: sample, search: StubSearch(), geocoder: StubGeocoder(), drives: StubDrives(),
                           scout: nil, sampleWeather: sample, ephemeris: CountingEphemeris(positions: positions),
                           defaults: UserDefaults(suiteName: "SpotCache-\(UUID().uuidString)")!, now: { fixedNow })
        let spot = try #require(CuratedSpots.all.first)
        let other = try #require(CuratedSpots.all.last { $0.coordinate.cacheKey != spot.coordinate.cacheKey })
        _ = await app.forecasts.load(spot.coordinate)
        let page = SpotModel(app: app, spot: spot, initialDay: app.today(in: spot.timeZone))
        _ = page.paths
        _ = page.rose
        let before = positions.value
        #expect(before > 0)
        // Another place's forecast bumps the centre's revision; this page's light has not changed.
        _ = await app.forecasts.load(other.coordinate)
        _ = page.paths
        _ = page.rose
        #expect(positions.value == before)
        // Its own forecast changing does recompute.
        app.forecasts.invalidateAll()
        _ = page.paths
        #expect(positions.value > before)
    }
}
