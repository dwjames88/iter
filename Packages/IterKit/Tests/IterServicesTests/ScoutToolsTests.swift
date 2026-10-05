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
