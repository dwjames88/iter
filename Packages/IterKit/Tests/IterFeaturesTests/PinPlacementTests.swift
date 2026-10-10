import Foundation
import Synchronization
import Testing
import IterCore
import IterData
import IterServices
@testable import IterFeatures

private let denver = TimeZone(identifier: "America/Denver")!
private let fixedNow = LocalDay(year: 2026, month: 10, day: 6).at(hour: 10, in: denver)

/// Counts forecast fetches per coordinate cell.
private final class CountingWeather: WeatherProviding {
    private let state = Mutex<[String]>([])
    var source: ForecastSource { .openWeather }
    var calls: [String] { state.withLock { $0 } }
    func forecast(for coordinate: Coordinate) async throws -> Forecast {
        state.withLock { $0.append(coordinate.cacheKey) }
        return Forecast(coordinate: coordinate, hours: [], days: [], fetchedAt: fixedNow, source: .openWeather)
    }
    func attribution() async -> WeatherAttributionInfo? { nil }
}

/// A geocoder that answers a different place, about 2 km from wherever you ask.
private struct FarGeocoder: Geocoding {
    func reverseGeocode(_ c: Coordinate) async throws -> PlaceResult {
        PlaceResult(id: "far", name: "Cafe Down the Road", locality: "Moab, UT",
                    coordinate: Coordinate(latitude: c.latitude + 0.018, longitude: c.longitude),
                    timeZoneIdentifier: "America/Denver", pointOfInterestCategory: nil)
    }
    func geocode(_ query: String) async throws -> [PlaceResult] { [] }
}

private struct NoDrives: DriveTimeProviding {
    func drive(from a: Coordinate, to b: Coordinate) async throws -> DriveLeg { DriveLeg.estimate(from: a, to: b) }
}

@MainActor
private func makeExplore(weather: CountingWeather) -> ExploreModel {
    let store = IterStore(container: try! IterSchema.makeContainer(inMemory: true))
    let clock: @Sendable () -> Date = { fixedNow }
    let sample = CachedWeatherService(wrapping: SampleWeatherService(now: clock))
    let defaults = UserDefaults(suiteName: "PinPlacement-\(UUID().uuidString)")!
    let app = AppModel(store: store, weather: weather, search: NoSearch(), geocoder: FarGeocoder(), drives: NoDrives(), scout: nil,
                       location: UserLocationModel(defaults: defaults), sampleWeather: sample, defaults: defaults, now: { fixedNow })
    let explore = ExploreModel(app: app, searchDebounce: .zero, defaults: defaults)
    explore.scoringDelay = .milliseconds(1)
    return explore
}

private struct NoSearch: PlaceSearching {
    func search(_ query: String, near region: GeoRegion?) async throws -> [PlaceResult] { [] }
    func pointsOfInterest(near center: Coordinate, radiusMeters: Double, categories: [String]) async throws -> [PlaceResult] { [] }
}

@MainActor
@Suite struct PinPlacementTests {
    private let beach = Coordinate(latitude: 36.55, longitude: -121.95)

    // MARK: The no-snap rule

    @Test func aLookupTwoKilometresAwayNeverMovesTheDroppedPin() async throws {
        let explore = makeExplore(weather: CountingWeather())
        var draft = SpotDraft(coordinate: beach)
        let answer = try await explore.app.geocoder.reverseGeocode(beach)
        #expect(answer.coordinate.distance(to: beach) > 1_900)
        draft.apply(lookup: answer, fillName: true, fillLocality: true)
        #expect(draft.coordinate == beach)
        #expect(draft.name == "Cafe Down the Road")
        let record = explore.app.store.createUserSpot(name: draft.trimmedName, coordinate: draft.coordinate,
                                                      timeZoneIdentifier: draft.timeZoneIdentifier)
        #expect(record.coordinate == beach)
        #expect(record.spot.coordinate == beach)
    }

    @Test func chipsAndTheSelectedPinShareOneAnchorSoSelectingDoesNotJump() {
        // The chip was anchored at its centre and the selected pin at its pointer tip: selecting a pin moved it up by its height.
        #expect(MapPinAnchor.vertical(for: .chip) == MapPinAnchor.vertical(for: .selected))
        #expect(MapPinAnchor.vertical(for: .selected) == 1, "the pointer's tip is the coordinate")
        #expect(MapPinAnchor.vertical(for: .dot) == 0.5)
        #expect(MapPinAnchor.horizontal == 0.5)
    }

    // MARK: Drag

    @Test func draggingAnOwnSpotMovesItLiveAndCommitsOnDropThenRefetches() async throws {
        let weather = CountingWeather()
        let explore = makeExplore(weather: weather)
        let record = explore.app.store.createUserSpot(name: "Beach", coordinate: beach, timeZoneIdentifier: "America/Los_Angeles")
        explore.app.spotSaved(record.spot)
        explore.didCreate(record.spot)
        let id = record.spot.id
        #expect(explore.canMove(id))

        let target = Coordinate(latitude: 36.56, longitude: -121.94)
        #expect(explore.beginDrag(id))
        explore.drag(to: target)
        #expect(explore.displayCoordinate(for: id, stored: beach) == target)
        #expect(record.coordinate == beach, "nothing is stored until the drop")
        explore.endDrag(commit: true)
        #expect(record.coordinate == target)
        #expect(explore.dragging == nil)
        #expect(explore.row(id: id)?.spot.coordinate == target)
        for _ in 0..<200 where !weather.calls.contains(target.cacheKey) { try await Task.sleep(for: .milliseconds(5)) }
        #expect(weather.calls.contains(target.cacheKey), "a new forecast is fetched for the new place")
    }

    @Test func cancellingADragStoresNothing() async throws {
        let explore = makeExplore(weather: CountingWeather())
        let record = explore.app.store.createUserSpot(name: "Beach", coordinate: beach, timeZoneIdentifier: "America/Los_Angeles")
        explore.didCreate(record.spot)
        #expect(explore.beginDrag(record.spot.id))
        explore.drag(to: Coordinate(latitude: 1, longitude: 1))
        explore.endDrag(commit: false)
        #expect(record.coordinate == beach)
        #expect(explore.displayCoordinate(for: record.spot.id, stored: beach) == beach)
    }

    @Test func curatedAndFoundSpotsCannotBeDragged() async throws {
        let explore = makeExplore(weather: CountingWeather())
        #expect(!explore.canMove("mesa-arch"))
        #expect(!explore.beginDrag("mesa-arch"))
        #expect(!explore.beginAdjusting("mesa-arch"))
    }

    // MARK: Adjust Location

    @Test func adjustLocationSavesTheCentreOnDoneAndRestoresOnCancel() async throws {
        let weather = CountingWeather()
        let explore = makeExplore(weather: weather)
        let record = explore.app.store.createUserSpot(name: "Beach", coordinate: beach, timeZoneIdentifier: "America/Los_Angeles")
        explore.didCreate(record.spot)
        let id = record.spot.id

        #expect(explore.beginAdjusting(id))
        #expect(explore.adjusting?.id == id)
        #expect(explore.adjusting?.original == beach)
        let centre = Coordinate(latitude: 36.552, longitude: -121.949)
        explore.adjustCenterChanged(centre)
        #expect(record.coordinate == beach, "the pin is the crosshair until Done")
        explore.finishAdjusting(commit: false)
        #expect(record.coordinate == beach && explore.adjusting == nil)

        #expect(explore.beginAdjusting(id))
        explore.adjustCenterChanged(centre)
        explore.finishAdjusting(commit: true)
        #expect(record.coordinate == centre && explore.adjusting == nil)
        for _ in 0..<200 where !weather.calls.contains(centre.cacheKey) { try await Task.sleep(for: .milliseconds(5)) }
        #expect(weather.calls.contains(centre.cacheKey))
    }

    @Test func movingToTypedCoordinatesGoesThroughTheSamePath() async throws {
        let explore = makeExplore(weather: CountingWeather())
        let record = explore.app.store.createUserSpot(name: "Beach", coordinate: beach, timeZoneIdentifier: "America/Los_Angeles")
        explore.didCreate(record.spot)
        let typed = try #require(CoordinateParser.parse("36.6, -121.9"))
        explore.move(record.spot.id, to: typed)
        #expect(record.coordinate == typed)
    }
}

@MainActor
@Suite struct CoordinateFieldsTests {
    @Test func typedTextBecomesACoordinateOnlyWhenBothAreValid() {
        var fields = CoordinateFields(Coordinate(latitude: 38.5, longitude: -109.5))
        #expect(fields.latitudeText == "38.5" && fields.longitudeText == "-109.5")
        #expect(fields.coordinate == Coordinate(latitude: 38.5, longitude: -109.5))
        fields.latitudeText = "91"
        #expect(fields.coordinate == nil)
        #expect(fields.latitudeProblem != nil && fields.longitudeProblem == nil)
        fields.latitudeText = "abc"
        #expect(fields.latitudeProblem != nil)
        fields.latitudeText = "40"
        fields.longitudeText = "-181"
        #expect(fields.longitudeProblem != nil && fields.coordinate == nil)
        fields.longitudeText = ""
        #expect(fields.longitudeProblem != nil)
        fields.longitudeText = "-100"
        #expect(fields.coordinate == Coordinate(latitude: 40, longitude: -100))
    }

    @Test func pastingFillsBothFieldsAndReportsFailure() {
        var fields = CoordinateFields(Coordinate(latitude: 0, longitude: 0))
        let linked = fields.paste("https://maps.apple.com/place?coordinate=38.573,-109.5494&name=Arch")
        #expect(linked)
        #expect(fields.coordinate == Coordinate(latitude: 38.573, longitude: -109.5494))
        let junk = fields.paste("not a place")
        #expect(!junk)
        #expect(fields.coordinate == Coordinate(latitude: 38.573, longitude: -109.5494), "a failed paste changes nothing")
        #expect(fields.pasteFailed)
        let dms = fields.paste("38.5°N 109.5°W")
        #expect(dms)
        #expect(!fields.pasteFailed)
    }

    @Test func settingTheCoordinateRewritesTheText() {
        var fields = CoordinateFields(Coordinate(latitude: 1, longitude: 2))
        fields.set(Coordinate(latitude: 36.123456789, longitude: -121.5))
        #expect(fields.latitudeText == "36.123457" && fields.longitudeText == "-121.5")
    }
}
