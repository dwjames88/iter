import Foundation
import Synchronization
import Testing
import IterCore
import IterData
import IterServices
@testable import IterFeatures

private let fixedNow = LocalDay(year: 2026, month: 10, day: 6).at(hour: 10, in: TimeZone(identifier: "America/Denver")!)

private final class Fetches: WeatherProviding {
    private let state = Mutex<[String]>([])
    var source: ForecastSource { .openWeather }
    var calls: [String] { state.withLock { $0 } }
    func forecast(for coordinate: Coordinate) async throws -> Forecast {
        state.withLock { $0.append(coordinate.cacheKey) }
        return Forecast(coordinate: coordinate, hours: [], days: [], fetchedAt: fixedNow, source: .openWeather)
    }
    func attribution() async -> WeatherAttributionInfo? { nil }
}

private struct NoSearch: PlaceSearching {
    func search(_ query: String, near region: GeoRegion?) async throws -> [PlaceResult] { [] }
    func pointsOfInterest(near center: Coordinate, radiusMeters: Double, categories: [String]) async throws -> [PlaceResult] { [] }
}

private struct NoGeocoder: Geocoding {
    func reverseGeocode(_ c: Coordinate) async throws -> PlaceResult { throw CancellationError() }
    func geocode(_ query: String) async throws -> [PlaceResult] { [] }
}

private struct NoDrives: DriveTimeProviding {
    func drive(from a: Coordinate, to b: Coordinate) async throws -> DriveLeg { DriveLeg.estimate(from: a, to: b) }
}

@MainActor
@Suite struct OwnPinDragModelTests {
    private let beach = Coordinate(latitude: 36.55, longitude: -121.95)
    private let target = Coordinate(latitude: 36.5612345, longitude: -121.9412345)

    private func app(weather: Fetches = Fetches()) -> AppModel {
        let store = IterStore(container: try! IterSchema.makeContainer(inMemory: true))
        let clock: @Sendable () -> Date = { fixedNow }
        let sample = CachedWeatherService(wrapping: SampleWeatherService(now: clock))
        let defaults = UserDefaults(suiteName: "OwnPinDrag-\(UUID().uuidString)")!
        return AppModel(store: store, weather: weather, search: NoSearch(), geocoder: NoGeocoder(), drives: NoDrives(), scout: nil,
                        location: UserLocationModel(defaults: defaults), sampleWeather: sample, defaults: defaults, now: { fixedNow })
    }

    @Test func holdAndPointerRulesAreSharedValues() {
        #expect(PinDrag.holdSeconds == 0.3)
        #expect(PinDrag.pointerMinimumDistance == 3)
        #expect(PinDrag.liftPoints == 5)
    }

    @Test func aDragMovesLiveAndCommitsOnDropAsOneMoveSpotUndoThenRefetches() async throws {
        let weather = Fetches()
        let app = app(weather: weather)
        let undo = UndoManager()
        undo.groupsByEvent = false
        app.store.undoManager = undo
        undo.beginUndoGrouping()
        let record = app.store.createUserSpot(name: "Beach", coordinate: beach, timeZoneIdentifier: "America/Los_Angeles")
        undo.endUndoGrouping()
        let id = record.spot.id
        var began: [String] = []
        let model = OwnPinDragModel(app: app) { began.append($0) }

        #expect(model.canMove(id))
        #expect(model.beginDrag(id))
        #expect(began == [id], "the map is told so it can select the pin")
        model.drag(to: Coordinate(latitude: 36.555, longitude: -121.945))
        model.drag(to: target)
        #expect(model.displayCoordinate(for: id, stored: beach) == target)
        #expect(model.displayCoordinate(for: "other", stored: beach) == beach)
        #expect(record.coordinate == beach, "nothing is stored until the drop")
        undo.beginUndoGrouping()
        model.endDrag(commit: true)
        undo.endUndoGrouping()
        #expect(model.dragging == nil)
        #expect(record.coordinate == target, "stored exactly")
        #expect(undo.undoActionName == "moveSpot")  // the app names it "Move Spot" (StoreActionText)
        for _ in 0..<200 where !weather.calls.contains(target.cacheKey) { try await Task.sleep(for: .milliseconds(5)) }
        #expect(weather.calls.contains(target.cacheKey), "the event is scored again at the new place")
        #expect(!weather.calls.contains(Coordinate(latitude: 36.555, longitude: -121.945).cacheKey))
        undo.undo()
        #expect(record.coordinate == beach, "one undo puts it back")
    }

    @Test func aDropWhereItStartedIsNoUndoStepAndNoFetch() async throws {
        let weather = Fetches()
        let app = app(weather: weather)
        let undo = UndoManager()
        undo.groupsByEvent = false
        app.store.undoManager = undo
        undo.beginUndoGrouping()
        let record = app.store.createUserSpot(name: "Beach", coordinate: beach, timeZoneIdentifier: "America/Los_Angeles")
        undo.endUndoGrouping()
        undo.removeAllActions()
        let model = OwnPinDragModel(app: app)
        #expect(model.beginDrag(record.spot.id))
        model.drag(to: beach)
        undo.beginUndoGrouping()
        model.endDrag(commit: true)
        undo.endUndoGrouping()
        #expect(undo.undoActionName.isEmpty, "no Move Spot step")
        try await Task.sleep(for: .milliseconds(50))
        #expect(weather.calls.isEmpty)
    }

    @Test func aCancelledDragStoresNothing() {
        let app = app()
        let record = app.store.createUserSpot(name: "Beach", coordinate: beach, timeZoneIdentifier: "America/Los_Angeles")
        let model = OwnPinDragModel(app: app)
        #expect(model.beginDrag(record.spot.id))
        model.drag(to: target)
        model.endDrag(commit: false)
        #expect(record.coordinate == beach)
        #expect(model.dragging == nil)
        #expect(model.displayCoordinate(for: record.spot.id, stored: beach) == beach)
    }

    @Test func spotsThatAreNotYoursAreRefused() throws {
        let app = app()
        app.store.setSaved(CuratedSpots.all[0], true)
        let saved = try #require(app.store.savedPlaces().first)
        var began = 0
        let model = OwnPinDragModel(app: app) { _ in began += 1 }
        #expect(!model.canMove(saved.id.uuidString), "saved from the catalogue: Apple's and ours")
        #expect(!model.beginDrag(saved.id.uuidString))
        #expect(!model.canMove(CuratedSpots.all[0].id))
        #expect(!model.canMove(UUID().uuidString))
        #expect(!model.beginDrag("mesa-arch"))
        #expect(began == 0 && model.dragging == nil)
        model.drag(to: target)
        #expect(model.dragging == nil, "no drag, nothing to move")
    }

    @Test func exploreAndTheOwnPinModelShareTheHostContract() {
        func canMove(_ host: some PinDragHost, _ id: String) -> Bool { host.canMove(id) }
        let app = app()
        let record = app.store.createUserSpot(name: "Beach", coordinate: beach, timeZoneIdentifier: "America/Los_Angeles")
        let explore = ExploreModel(app: app, searchDebounce: .zero, defaults: UserDefaults(suiteName: "OwnPinDragX-\(UUID().uuidString)")!)
        #expect(canMove(explore, record.spot.id) && canMove(OwnPinDragModel(app: app), record.spot.id))
    }
}
