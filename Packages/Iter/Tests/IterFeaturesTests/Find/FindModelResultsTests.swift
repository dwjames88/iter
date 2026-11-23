import Foundation
import Testing
import IterModel
import IterSources
import IterStore
import IterDiscovery
@testable import IterFeatures

@MainActor
@Suite("FindModel: results, drive times, card")
struct FindModelResultsTests {
    @Test func orderingChangesReorderWithoutAnotherSearch() async throws {
        let counting = CountingRunner(FindFixtures.engine())
        let rig = try Rig(runner: counting)
        rig.preferences.ordering = .popular
        await rig.search()
        let popular = rig.model.rows.map(\.name)
        #expect(popular.first == "Mesa Arch")
        rig.model.ordering = .unique
        let unique = rig.model.rows.map(\.name)
        #expect(unique != popular)
        #expect(unique.first != "Mesa Arch")
        #expect(Set(unique) == Set(popular))
        #expect(rig.preferences.ordering == .unique)
        #expect(counting.runs == 1)
        rig.model.ordering = .popular
        #expect(rig.model.rows.map(\.name) == popular)
    }

    @Test func kindFiltersListWhatIsPresentAndNarrowTheRows() async throws {
        let rig = try Rig()
        await rig.search()
        #expect(rig.model.kindFilters.map(\.kind) == [.arch, .viewpoint])
        #expect(rig.model.kindFilters.first { $0.kind == .arch }?.count == 1)
        rig.model.toggleKind(.arch)
        #expect(rig.model.rows.map(\.name) == ["Mesa Arch"])
        #expect(rig.model.kindFilters.first { $0.kind == .arch }?.isOn == true)
        #expect(rig.model.kindFilters.first { $0.kind == .viewpoint }?.count == 6)
        rig.model.clearKindFilters()
        #expect(rig.model.rows.count == 6)
    }

    @Test func lightSuitIsHonestlyUnknownWithoutAFacing() async throws {
        let rig = try Rig()
        await rig.search()
        #expect(rig.model.rows.allSatisfy { !$0.lightSuit.facingKnown && $0.lightSuit.value == nil })
        #expect(rig.model.rows.first?.lightSuit.text == "Light suit unknown: no facing")
    }

    @Test func driveTimesAreStraightLineUntilTheRouterAnswers() async throws {
        let routing = FindFixtures.Routing(delay: .milliseconds(120))
        let rig = try Rig(routing: routing)
        await rig.search()
        #expect(rig.model.rows.allSatisfy { $0.drive?.basis == .straightLine })
        #expect(rig.model.rows.first?.drive?.text.contains("straight-line") == true)
        #expect(rig.model.rows.contains { $0.isFetchingDrive })
        #expect(await waitUntil(.seconds(20)) { rig.model.rows.allSatisfy { $0.drive?.basis == .drive } })
        #expect(rig.model.rows.allSatisfy { !$0.isFetchingDrive })
        #expect(rig.model.rows.first?.drive?.text.hasSuffix("drive") == true)
        #expect(routing.calls == 6)
        // One or two at a time.
        #expect(routing.peakConcurrency <= 2 && routing.peakConcurrency >= 1)
    }

    @Test func onlyTheTopResultsAreRouted() async throws {
        let routing = FindFixtures.Routing()
        var config = Rig.fastFind
        config.driveTimeCount = 3
        let rig = try Rig(routing: routing, configuration: config)
        await rig.search()
        #expect(await waitUntil { rig.model.rows.filter { $0.drive?.basis == .drive }.count == 3 })
        try await Task.sleep(for: .milliseconds(50))
        #expect(routing.calls == 3)
        #expect(rig.model.rows.filter { $0.drive?.basis == .straightLine }.count == 3)
    }

    @Test func cancellingStopsRoutingAndKeepsStraightLineLabels() async throws {
        let routing = FindFixtures.Routing(hangs: true)
        let rig = try Rig(routing: routing)
        await rig.search()
        #expect(await waitUntil { routing.calls >= 2 })
        rig.model.cancel()
        #expect(await waitUntil { routing.cancelledCalls >= 2 })
        #expect(rig.model.rows.allSatisfy { !$0.isFetchingDrive && $0.drive?.basis == .straightLine })
        let calls = routing.calls
        try await Task.sleep(for: .milliseconds(60))
        #expect(routing.calls == calls)
    }

    @Test func aNewSearchDropsDriveTimesOfTheOldOne() async throws {
        let rig = try Rig()
        await rig.search()
        #expect(await waitUntil { rig.model.rows.allSatisfy { $0.drive?.basis == .drive } })
        rig.model.askIter()
        #expect(rig.model.rows.isEmpty)
        #expect(await waitUntil { rig.model.phase == .finished })
        #expect(await waitUntil { rig.model.rows.allSatisfy { $0.drive?.basis == .drive } })
    }

    @Test func withoutALocationNothingIsRoutedAndNoTimeIsClaimed() async throws {
        let routing = FindFixtures.Routing()
        let rig = try Rig(location: nil, routing: routing)
        await rig.search()
        try await Task.sleep(for: .milliseconds(60))
        #expect(routing.calls == 0)
        #expect(rig.model.rows.allSatisfy { $0.drive == nil && $0.distanceBasis == .fromAreaCentre })
        #expect(rig.model.rows.first?.distanceText?.hasSuffix("from the search centre") == true)
    }

    @Test func selectingAResultBuildsTheCard() async throws {
        let rig = try Rig()
        await rig.search()
        let mesa = try #require(rig.model.rows.first { $0.name == "Mesa Arch" })
        rig.model.select(mesa.id)
        let card = try #require(rig.model.card)
        #expect(card.kind == .discovered && card.name == "Mesa Arch")
        #expect(card.verificationLabel?.hasPrefix("Confirmed by") == true)
        #expect(card.sourceNames.contains("OpenStreetMap (Overpass)"))
        #expect(card.why?.isEmpty == false)
        #expect(card.distanceText?.hasSuffix("from you") == true)
        #expect(!card.lightSuit.facingKnown)
        #expect(rig.model.mapsTarget?.coordinate == mesa.coordinate)
        // Look Around: covered near Mesa Arch, not at the far overlook.
        #expect(await waitUntil { rig.model.lookAround == .available })
        let far = try #require(rig.model.rows.first { $0.name == "Grand View Point Overlook" })
        rig.model.select(far.id)
        #expect(await waitUntil { rig.model.lookAround == .satelliteFallback })
        rig.model.deselect()
        #expect(rig.model.card == nil && rig.model.lookAround == .unknown)
    }

    @Test func noStreetLevelProviderMeansTheSatelliteFallback() async throws {
        let rig = try Rig(streetLevel: nil)
        await rig.search()
        rig.model.select(rig.model.rows[0].id)
        #expect(rig.model.lookAround == .satelliteFallback)
    }

    @Test func saveToggleStoresTheDiscoveredPlaceWithItsProvenance() async throws {
        let rig = try Rig()
        await rig.search()
        let mesa = try #require(rig.model.rows.first { $0.name == "Mesa Arch" })
        rig.model.select(mesa.id)
        #expect(rig.model.card?.isSaved == false)
        await rig.model.setSaved(true)
        #expect(rig.model.card?.isSaved == true)
        #expect(rig.model.rows.first { $0.id == mesa.id }?.isSaved == true)
        let saved = try #require(rig.library.places.savedValues().first)
        #expect(saved.name == "Mesa Arch" && saved.origin == .scout && saved.verification == .confirmed)
        #expect(!saved.citations.isEmpty && saved.sources.contains(FindFixtures.osm))
        // The real zone from the reverse lookup, not the longitude estimate.
        #expect(saved.timeZoneIdentifier == "America/Denver")
        await rig.model.setSaved(false)
        #expect(rig.library.places.savedValues().isEmpty)
        #expect(rig.model.rows.first { $0.id == mesa.id }?.isSaved == false)
        // Saving twice keeps one record.
        await rig.model.setSaved(true)
        await rig.model.setSaved(true)
        #expect(rig.library.places.savedValues().count == 1)
    }

    @Test func addToTripListsTripsAndAddsTheStop() async throws {
        let rig = try Rig()
        await rig.search()
        let existing = rig.library.trips.create(name: "Canyon Country", startDay: LocalDay(year: 2026, month: 11, day: 3), dayCount: 3)
        rig.model.select(rig.model.rows.first { $0.name == "Mesa Arch" }!.id)
        #expect(rig.model.tripChoices().map(\.name) == ["Canyon Country"])
        #expect(rig.model.addToTrip(existing.id, day: 1))
        #expect(existing.orderedStops(onDay: 1).map(\.place?.name) == ["Mesa Arch"])
        #expect(!rig.model.addToTrip(UUID()))
        let newID = try #require(rig.model.addToNewTrip(named: "Utah Sunrise", startDay: LocalDay(year: 2026, month: 12, day: 1)))
        #expect(rig.library.trips.value(id: newID)?.name == "Utah Sunrise")
        #expect(rig.library.trips.trip(id: newID)?.orderedStops(onDay: 0).count == 1)
        #expect(rig.model.tripChoices().count == 2)
    }

    @Test func mapContentHasPinsOutlineAndClusters() async throws {
        let rig = try Rig()
        await rig.search()
        #expect(rig.model.mapContent.pins.count == 6)
        #expect(rig.model.mapContent.clusters.isEmpty)
        #expect(rig.model.mapContent.areaRegion != nil)
        // Zoomed far out the 6 places share a cell.
        rig.model.setViewport(region: GeoRegion(center: FindFixtures.canyonlands, latitudeDelta: 40, longitudeDelta: 40), width: 600)
        #expect(rig.model.mapContent.clusters.reduce(0) { $0 + $1.count } + rig.model.mapContent.pins.count >= 6)
        #expect(!rig.model.mapContent.clusters.isEmpty)
        // Zoomed in, nothing is clustered.
        rig.model.setViewport(region: GeoRegion(center: FindFixtures.mesaArch, latitudeDelta: 0.04, longitudeDelta: 0.05), width: 600)
        #expect(rig.model.mapContent.clusters.isEmpty)
    }

    @Test func ownSpotsNeverCluster() async throws {
        let rig = try Rig()
        for i in 0..<4 {
            _ = rig.library.places.createUserSpot(name: "Spot \(i)", coordinate: Coordinate(latitude: 38.3884 + Double(i) * 0.0001, longitude: -109.868),
                                                  timeZoneIdentifier: "America/Denver")
        }
        rig.model.refreshLibraryPins()
        rig.model.setViewport(region: GeoRegion(center: FindFixtures.mesaArch, latitudeDelta: 60, longitudeDelta: 60), width: 400)
        #expect(rig.model.mapContent.pins.filter { $0.kind == .own }.count == 4)
        #expect(rig.model.mapContent.clusters.isEmpty)
    }

    @Test func typedLookupListsSavedPlacesThenAppleMaps() async throws {
        let runner = ControlledRunner()
        let rig = try Rig(runner: runner)
        _ = rig.library.places.createUserSpot(name: "Mesa Trail Pond", coordinate: FindFixtures.moab, timeZoneIdentifier: "America/Denver")
        rig.model.text = "Mesa"
        rig.model.submit()
        #expect(runner.requests.isEmpty)
        #expect(await waitUntil { rig.model.phase == .finished })
        #expect(rig.model.matches.first?.origin == .saved)
        #expect(rig.model.matches.first?.name == "Mesa Trail Pond")
        #expect(rig.model.matches.contains { $0.origin == .appleMaps && $0.name == "Mesa Arch" })
        rig.model.select(rig.model.matches.first { $0.origin == .appleMaps }!.id)
        #expect(rig.model.card?.kind == .match)
        await rig.model.setSaved(true)
        #expect(rig.library.places.savedValues().contains { $0.name == "Mesa Arch" })
    }

    @Test func aLookupThatHangsTimesOutAndKeepsSavedMatches() async throws {
        struct Hang: PlaceSearchProvider {
            var descriptor = FindFixtures.descriptor(.appleSearch, "Apple Maps", kinds: [.places])
            func search(_ text: String, near region: GeoRegion) async throws -> [PlaceCandidate] {
                try await Task.sleep(for: .seconds(3600))
                return []
            }
        }
        var config = Rig.fastFind
        config.lookupTimeout = .milliseconds(100)
        let rig = try Rig(placeSearch: Hang(), configuration: config)
        _ = rig.library.places.createUserSpot(name: "Mesa Trail Pond", coordinate: FindFixtures.moab, timeZoneIdentifier: "America/Denver")
        rig.model.text = "Mesa"
        rig.model.submit()
        #expect(rig.model.matches.count == 1)
        #expect(await waitUntil { rig.model.phase == .finished })
        #expect(rig.model.matches.count == 1)
    }
}
