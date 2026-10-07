import Foundation
import IterCore
import Testing
@testable import IterServices

@Suite("Scout tools")
struct ScoutToolsTests {
    @Test func findPlacesRegistersIDsAndBuildsTable() async throws {
        let registry = ScoutRegistry()
        let log = ProgressLog()
        let ctx = Fixture.context(search: FakeSearch(results: [Fixture.cannonBeach, Fixture.silverFalls, Fixture.farAway]),
                                  registry: registry, progress: { log.add($0) })
        let table = try await FindPlacesTool(context: ctx).call(arguments: .init(query: "foggy forest", near: "Portland, Oregon", radiusKilometers: 200))

        #expect(table.contains("m1 | Cannon Beach"))              // search relevance order is kept
        #expect(table.contains("m2 | Silver Falls State Park"))
        #expect(!table.contains("Yellowstone"))                   // outside the radius
        #expect(table.contains("Park |"))                         // kind from the POI category
        #expect(await registry.place("m2")?.name == "Silver Falls State Park")
        #expect(await registry.place("m3") == nil)
        #expect(log.all.contains(.searching("Portland, Oregon")))
    }

    @Test func findPlacesFallsBackToScenicPOIsWhenSearchIsThin() async throws {
        let ctx = Fixture.context(search: FakeSearch(results: [], scenic: [Fixture.silverFalls]))
        let table = try await FindPlacesTool(context: ctx).call(arguments: .init(query: "x", near: "Portland", radiusKilometers: 100))
        #expect(table.contains("Silver Falls State Park"))
    }

    @Test func wideSearchesDropTheCityCore() async throws {
        let downtown = Fixture.place("apple-d", "Pioneer Courthouse Square", lat: 45.5189, lon: -122.6795, poi: "MKPOICategoryPark")
        let ctx = Fixture.context(search: FakeSearch(results: [downtown, Fixture.silverFalls]))
        let wide = try await FindPlacesTool(context: ctx).call(arguments: .init(query: "park", near: "Portland", radiusKilometers: 150))
        #expect(!wide.contains("Pioneer") && wide.contains("Silver Falls"))
        let narrow = try await FindPlacesTool(context: Fixture.context(search: FakeSearch(results: [downtown])))
            .call(arguments: .init(query: "park", near: "Portland", radiusKilometers: 10))
        #expect(narrow.contains("Pioneer"))
    }

    @Test func findPlacesWithNothingSaysSo() async throws {
        let ctx = Fixture.context()
        let text = try await FindPlacesTool(context: ctx).call(arguments: .init(query: "x", near: "Portland", radiusKilometers: 50))
        #expect(text.hasPrefix("No places found"))
    }

    @Test func unknownCentreIsReported() async throws {
        let ctx = ScoutToolContext(search: FakeSearch(results: []), geocoder: FakeGeocoder(centre: nil), drives: nil, curated: [],
                                   registry: ScoutRegistry(), progress: { _ in })
        let text = try await FindPlacesTool(context: ctx).call(arguments: .init(query: "x", near: "Nowhereville", radiusKilometers: 50))
        #expect(text.contains("No place found"))
    }

    @Test func curatedToolFiltersByDistanceCategoryAndLight() async throws {
        let registry = ScoutRegistry()
        let ctx = Fixture.context(curated: [Fixture.curatedSpot, Fixture.curatedCoast], registry: registry)
        let tool = CuratedSpotsTool(context: ctx)

        let all = try await tool.call(arguments: .init(near: "Portland", radiusKilometers: 200, category: nil, light: nil))
        #expect(all.contains("c:multnomah-falls | Multnomah Falls"))
        #expect(all.contains("best: overcast/sunrise"))
        #expect(all.contains("Haystack Rock"))
        #expect(await registry.place("c:multnomah-falls") != nil)

        let near = try await tool.call(arguments: .init(near: "Portland", radiusKilometers: 50, category: nil, light: nil))
        #expect(near.contains("Multnomah") && !near.contains("Haystack"))

        let waterfalls = try await tool.call(arguments: .init(near: "Portland", radiusKilometers: 200, category: .waterfall, light: nil))
        #expect(waterfalls.contains("Multnomah") && !waterfalls.contains("Haystack"))

        let sunset = try await tool.call(arguments: .init(near: "Portland", radiusKilometers: 200, category: nil, light: .sunset))
        #expect(sunset.contains("Haystack") && !sunset.contains("Multnomah"))
    }

    @Test func curatedFiltersRelaxWhenTheyMatchNothing() async throws {
        let ctx = Fixture.context(curated: [Fixture.curatedSpot])
        let text = try await CuratedSpotsTool(context: ctx).call(arguments: .init(near: "Portland", radiusKilometers: 200, category: .desert, light: nil))
        #expect(text.contains("no exact match") && text.contains("Multnomah"))
    }

    @Test func moodWordsAreStrippedFromQueries() {
        #expect(FindPlacesTool.featureQuery("foggy forest") == "forest")
        #expect(FindPlacesTool.featureQuery("Misty Sunrise") == "Misty Sunrise") // nothing left, so the original is kept
        #expect(FindPlacesTool.featureQuery("old-growth forest trail") == "old-growth forest trail")
    }

    @Test func driveToolRecordsMinutesAndHonoursTheBudget() async throws {
        let registry = ScoutRegistry()
        let drives = FakeDrives()
        let log = ProgressLog()
        let ctx = Fixture.context(search: FakeSearch(results: [Fixture.silverFalls]), drives: drives, registry: registry, progress: { log.add($0) })
        _ = try await FindPlacesTool(context: ctx).call(arguments: .init(query: "x", near: "Portland", radiusKilometers: 100))
        let tool = DriveTimeTool(context: ctx)

        let first = try await tool.call(arguments: .init(from: "Portland", placeID: "m1"))
        #expect(first.contains("90 min"))
        #expect(await registry.place("m1")?.driveSeconds == 5400)
        #expect(log.all.contains(.checkingDrive("Silver Falls State Park")))

        for _ in 1..<ScoutRegistry.driveBudget { _ = try await tool.call(arguments: .init(from: "Portland", placeID: "m1")) }
        let over = try await tool.call(arguments: .init(from: "Portland", placeID: "m1"))
        #expect(over.contains("limit reached"))
        #expect(await drives.counter.calls == ScoutRegistry.driveBudget)
    }

    @Test func driveToolRejectsUnknownIDsWithoutSpendingBudget() async throws {
        let drives = FakeDrives()
        let ctx = Fixture.context(drives: drives)
        let text = try await DriveTimeTool(context: ctx).call(arguments: .init(from: "Portland", placeID: "m42"))
        #expect(text.contains("Unknown place ID"))
        #expect(await drives.counter.calls == 0)
        #expect(await ctx.registry.reserveDriveCall())
    }

    @Test func cancellationPropagatesThroughTools() async {
        struct Slow: PlaceSearching {
            func search(_ query: String, near region: GeoRegion?) async throws -> [PlaceResult] { throw CancellationError() }
            func pointsOfInterest(near center: Coordinate, radiusMeters: Double, categories: [String]) async throws -> [PlaceResult] { [] }
        }
        let ctx = ScoutToolContext(search: Slow(), geocoder: FakeGeocoder(centre: Fixture.portland), drives: nil, curated: [], registry: ScoutRegistry(), progress: { _ in })
        await #expect(throws: CancellationError.self) {
            _ = try await FindPlacesTool(context: ctx).call(arguments: .init(query: "x", near: "Portland", radiusKilometers: 50))
        }
    }

    @Test func regionCoversTheRadius() {
        let r = ScoutToolContext.region(around: Coordinate(latitude: 45, longitude: -122), radiusKilometers: 100)
        #expect(abs(r.latitudeDelta - 1.8) < 0.01)
        #expect(r.longitudeDelta > r.latitudeDelta)
    }
}

// MARK: - The map area (Ask in Explore)

private actor GeocodeCalls {
    var names: [String] = []
    func add(_ name: String) { names.append(name) }
}

private struct CountingGeocoder: Geocoding {
    var calls = GeocodeCalls()
    var centre: PlaceResult? = Fixture.portland
    func reverseGeocode(_ coordinate: Coordinate) async throws -> PlaceResult { throw CancellationError() }
    func geocode(_ query: String) async throws -> [PlaceResult] {
        await calls.add(query)
        return centre.map { [$0] } ?? []
    }
}

@Suite("Scout tools: the map area")
struct ScoutMapAreaTests {
    private let area = GeoRegion(center: Coordinate(latitude: 44.0, longitude: -122.0), latitudeDelta: 2, longitudeDelta: 3)

    private func context(area: GeoRegion?, geocoder: CountingGeocoder, search: FakeSearch = FakeSearch(results: []),
                         curated: [Spot] = []) -> ScoutToolContext {
        ScoutToolContext(search: search, geocoder: geocoder, drives: nil, curated: curated, registry: ScoutRegistry(),
                         progress: { _ in }, area: area)
    }

    @Test(arguments: ["the map", "The Map", "map", "here", "this area", " the map area. "])
    func mapPhrasesResolveToTheAreaCentreWithoutGeocoding(_ phrase: String) async throws {
        let geocoder = CountingGeocoder()
        let ctx = context(area: area, geocoder: geocoder)
        let centre = try #require(await ctx.centre(for: phrase))
        #expect(centre.coordinate == area.center)
        #expect(centre.name == "the map area")
        #expect(await geocoder.calls.names.isEmpty)
    }

    @Test func aRealPlaceNameStillGeocodes() async throws {
        let geocoder = CountingGeocoder()
        let ctx = context(area: area, geocoder: geocoder)
        let centre = try #require(await ctx.centre(for: "Portland, Oregon"))
        #expect(centre.coordinate == Fixture.portland.coordinate)
        #expect(await geocoder.calls.names == ["Portland, Oregon"])
    }

    @Test func withoutAnAreaTheMapIsJustAName() async throws {
        let geocoder = CountingGeocoder()
        let ctx = context(area: nil, geocoder: geocoder)
        _ = try await ctx.centre(for: "the map")
        #expect(await geocoder.calls.names == ["the map"])
    }

    @Test func findPlacesNearTheMapSearchesAroundTheAreaCentre() async throws {
        let geocoder = CountingGeocoder()
        let nearby = Fixture.place("apple-n", "Nearby Falls", lat: 44.1, lon: -122.1, poi: "MKPOICategoryPark")
        let ctx = context(area: area, geocoder: geocoder, search: FakeSearch(results: [nearby]))
        let table = try await FindPlacesTool(context: ctx).call(arguments: .init(query: "waterfall", near: "the map", radiusKilometers: 50))
        #expect(table.contains("Nearby Falls"))
        #expect(table.contains("distance from the map"))
        #expect(await geocoder.calls.names.isEmpty)
    }

    @Test func curatedSpotsNearTheMapUseTheAreaCentre() async throws {
        let geocoder = CountingGeocoder()
        let spot = Spot(id: "near-map", name: "Near Map Falls", locality: "OR", coordinate: Coordinate(latitude: 44.05, longitude: -122.02),
                        timeZoneIdentifier: "America/Los_Angeles", category: .waterfall, bestLight: [.overcast], origin: .curated)
        let ctx = context(area: area, geocoder: geocoder, curated: [spot, Fixture.curatedSpot])
        let table = try await CuratedSpotsTool(context: ctx).call(arguments: .init(near: "the map", radiusKilometers: 50, category: nil, light: nil))
        #expect(table.contains("Near Map Falls"))
        #expect(!table.contains("Multnomah"))          // ~130 km away
        #expect(await geocoder.calls.names.isEmpty)
    }

    @Test func theGatheringPromptNamesTheMapOnlyWhenThereIsAnArea() {
        #expect(AppleIntelligenceScout.gatheringInstructions(hasArea: true).contains(#"If the request names no place, use near: "the map"."#))
        #expect(AppleIntelligenceScout.gatheringInstructions(hasArea: true).contains(#"The map shows the area around "the map"."#))
        #expect(AppleIntelligenceScout.gatheringInstructions(hasArea: false) == AppleIntelligenceScout.gatheringInstructions)
    }
}
