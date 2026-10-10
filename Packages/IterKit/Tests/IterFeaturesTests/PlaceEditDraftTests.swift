import Foundation
import Synchronization
import Testing
import IterCore
import IterData
import IterServices
@testable import IterFeatures

private final class CountingWeather: WeatherProviding {
    private let keys = Mutex<[String]>([])
    var source: ForecastSource { .openWeather }
    var calls: [String] { keys.withLock { $0 } }
    func forecast(for coordinate: Coordinate) async throws -> Forecast {
        keys.withLock { $0.append(coordinate.cacheKey) }
        return Forecast(coordinate: coordinate, hours: [], days: [], fetchedAt: Date(timeIntervalSince1970: 1_790_000_000), source: .openWeather)
    }
    func attribution() async -> WeatherAttributionInfo? { nil }
}

private struct NoSearch: PlaceSearching, Geocoding, DriveTimeProviding {
    func search(_ query: String, near region: GeoRegion?) async throws -> [PlaceResult] { [] }
    func pointsOfInterest(near center: Coordinate, radiusMeters: Double, categories: [String]) async throws -> [PlaceResult] { [] }
    func reverseGeocode(_ coordinate: Coordinate) async throws -> PlaceResult { throw CancellationError() }
    func geocode(_ query: String) async throws -> [PlaceResult] { [] }
    func drive(from a: Coordinate, to b: Coordinate) async throws -> DriveLeg { .estimate(from: a, to: b) }
}

@MainActor
@Suite struct PlaceEditDraftTests {
    let undo = UndoManager()

    fileprivate func model(_ weather: CountingWeather = CountingWeather()) throws -> AppModel {
        let defaults = UserDefaults(suiteName: "PlaceEditDraftTests-\(UUID().uuidString)")!
        let store = IterStore(container: try IterSchema.makeContainer(inMemory: true))
        undo.groupsByEvent = false
        store.undoManager = undo
        return AppModel(store: store, weather: weather, search: NoSearch(), geocoder: NoSearch(), drives: NoSearch(),
                        scout: nil, sampleWeather: SampleWeatherService(now: { .now }), defaults: defaults, now: { .now })
    }

    func act<T>(_ body: () -> T) -> T {
        undo.beginUndoGrouping(); defer { undo.endUndoGrouping() }
        return body()
    }

    func ownSpot(_ model: AppModel) -> PlaceRecord {
        act { model.store.createUserSpot(name: "Pond", locality: "Bishop", coordinate: Coordinate(latitude: 37.3, longitude: -118.4),
                                         timeZoneIdentifier: "America/Los_Angeles", category: .landscape, bestLight: [.sunrise], notes: "n", walkInMinutes: 5) }
    }

    @Test func aBlankNameIsTheOnlyProblemOfAnOwnSpot() throws {
        let m = try model()
        var draft = PlaceEditDraft(ownSpot(m))
        #expect(draft.isValid)
        draft.name = "   "
        #expect(draft.problems == [.nameRequired])
        draft.name = "Pond"; draft.walkInText = "9999"
        #expect(draft.problems == [.walkInInvalid])
    }

    @Test func tagsAreTrimmedAndDeduplicated() throws {
        let m = try model()
        var draft = PlaceEditDraft(ownSpot(m))
        draft.tagsText = " lake, Quiet ,, lake, quiet "
        #expect(draft.tags == ["lake", "Quiet"])
    }

    @Test func doneSavesAndCancelDiscards() throws {
        let m = try model()
        let place = ownSpot(m)
        var draft = PlaceEditDraft(place)
        draft.name = "Cancelled"; draft.notes = "gone"
        // Cancel: the draft is dropped and never applied.
        #expect(place.name == "Pond" && place.notes == "n")
        draft.name = " Lake "; draft.locality = "CA"
        #expect(act { m.applyEdit(draft, to: place) })
        #expect(place.name == "Lake" && place.locality == "CA" && place.notes == "gone")
        #expect(undo.undoActionName == "updatePlace")  // the app names it "Edit Location" (StoreActionText)
    }

    @Test func aMovedCoordinateFetchesTheNewForecastAndUndoRestoresTheOld() async throws {
        let weather = CountingWeather()
        let m = try model(weather)
        let place = ownSpot(m)
        let old = place.coordinate
        var draft = PlaceEditDraft(place)
        draft.coordinate = Coordinate(latitude: 38.5, longitude: -119.25)
        #expect(draft.movesPlace)
        #expect(act { m.applyEdit(draft, to: place) })
        let moved = Coordinate(latitude: 38.5, longitude: -119.25)
        #expect(place.coordinate == moved)
        for _ in 0..<100 where !weather.calls.contains(moved.cacheKey) { try await Task.sleep(for: .milliseconds(50)) }
        #expect(weather.calls.contains(moved.cacheKey))
        undo.undo()
        #expect(place.coordinate == old)
    }

    @Test func aCuratedSpotLocksItsFactsAndSaysSo() throws {
        let m = try model()
        let curated = try #require(CuratedSpots.spot(id: "mesa-arch"))
        act { m.store.setSaved(curated, true) }
        let record = try #require(m.store.editableRecord(for: curated))
        var draft = PlaceEditDraft(record)
        #expect(!draft.editsFacts)
        draft.coordinate = Coordinate(latitude: 0, longitude: 0); draft.category = .urban
        #expect(draft.isValid && !draft.movesPlace)
        draft.name = "Mine"
        #expect(act { m.applyEdit(draft, to: record) })
        #expect(record.name == "Mine" && record.coordinate == curated.coordinate && record.category == curated.category)
    }
}
