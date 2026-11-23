import AppKit
import Foundation
import Testing
import IterFeatures
import IterModel
@testable import Iter

/// The shell without a window: composition, navigation, command availability, switches, and the import flow.
@MainActor @Suite struct ShellTests {
    // MARK: Composition

    @Test func hostLaunchesOnAnInMemoryStoreAndNeverTheRealOne() throws {
        // The host is the render copy launched with -IterInMemoryStore YES: AppContainer.live resolves .inMemory.
        guard case .ready(let shell) = LaunchResult.launch() else { Issue.record("launch failed"); return }
        #expect(shell.container.store.placement == .inMemory)
        #expect(shell.container.store.activeURL == nil)
    }

    @Test func renderBundleIDWithoutSwitchesStillResolvesInMemory() throws {
        let result = LaunchResult.launch(options: LaunchOptions(), bundleID: Snapshot.renderBundleID, environment: [:])
        guard case .ready(let shell) = result else { Issue.record("launch failed"); return }
        #expect(shell.container.store.placement == .inMemory)
    }

    @Test func aFailedOpenBecomesAFailureNotACrash() {
        struct Boom: Error {}
        let result = LaunchResult.launch(makeContainer: { throw Boom() })
        guard case .failed(let failure) = result else { Issue.record("expected a failure"); return }
        #expect(failure.message.contains("couldn't open your library"))
        #expect(failure.backupFolder.path.contains("Backups") || failure.backupFolder.path.contains("Iter"))
    }

    @Test func fixedLocationStartsAtLaunch() throws {
        var options = LaunchOptions()
        options.fixedLocation = Coordinate(latitude: 38.39, longitude: -109.87)
        let result = LaunchResult.launch(options: options, bundleID: Snapshot.renderBundleID, environment: [:])
        guard case .ready(let shell) = result else { Issue.record("launch failed"); return }
        #expect(shell.container.location.status == .fixed)
    }

    // MARK: Navigation

    @Test func everyRouteHasADetailView() {
        let id = UUID()
        let expected: [(AppRoute, DetailKind)] = [
            (.find, .find), (.allTrips, .allTrips), (.tripFolder(id), .allTrips), (.trip(id), .trip),
            (.savedPlaces, .savedPlaces), (.placeFolder(id), .savedPlaces), (.place(id), .place),
        ]
        for (route, kind) in expected { #expect(DetailKind(route) == kind, "\(route)") }
    }

    @Test func routesRoundTripThroughSceneStorage() {
        let id = UUID()
        for route in [AppRoute.find, .allTrips, .trip(id), .tripFolder(id), .savedPlaces, .placeFolder(id), .place(id)] {
            #expect(AppRoute(stored: route.stored) == route)
        }
        #expect(AppRoute(stored: "") == nil)
        #expect(AppRoute(stored: "not json") == nil)
    }

    @Test func sectionSwitchPicksTheRoute() {
        let id = UUID()
        #expect(AppRoute.forSection("find", firstTripID: id) == .find)
        #expect(AppRoute.forSection("trips", firstTripID: id) == .allTrips)
        #expect(AppRoute.forSection("places", firstTripID: id) == .savedPlaces)
        #expect(AppRoute.forSection("trip", firstTripID: id) == .trip(id))
        #expect(AppRoute.forSection("trip", firstTripID: nil) == .allTrips)
        #expect(AppRoute.forSection(nil, firstTripID: id) == nil)
        #expect(AppRoute.forSection("nonsense", firstTripID: id) == nil)
    }

    @Test func aGoneTripFallsBackToAllTrips() throws {
        let window = try makeWindow(seed: true)
        let id = try #require(window.library.trips.first?.id)
        window.navigator.open(.trip(id))
        window.validateRoute()
        #expect(window.route == .trip(id))
        window.library.deleteTrip(id)
        window.validateRoute()
        #expect(window.route == .allTrips)
        window.navigator.open(.trip(UUID()))
        window.restore(stored: AppRoute.trip(UUID()).stored)
        #expect(window.route == .allTrips)
    }

    @Test func titleFollowsTheRoute() throws {
        let window = try makeWindow(seed: true)
        #expect(window.title == "Find")
        window.navigator.open(.allTrips)
        #expect(window.title == "All Trips")
        let trip = try #require(window.library.trips.first)
        window.navigator.open(.trip(trip.id))
        #expect(window.title == trip.name)
    }

    // MARK: Commands

    @Test func commandAvailabilityFollowsTheRoute() {
        #expect(CommandAvailability(route: .trip(UUID())).tripCommands)
        #expect(CommandAvailability(route: .trip(UUID())).refreshConditions)
        #expect(!CommandAvailability(route: .trip(UUID())).editPlace)
        #expect(CommandAvailability(route: .place(UUID())).editPlace)
        #expect(CommandAvailability(route: .place(UUID())).refreshConditions)
        #expect(!CommandAvailability(route: .find).tripCommands)
        #expect(!CommandAvailability(route: .allTrips).refreshConditions)
        #expect(!CommandAvailability(route: nil).editPlace)
    }

    @Test func commandActionsAskTheNavigator() throws {
        let window = try makeWindow(seed: true)
        window.newTrip()
        #expect(window.navigator.sheet == .newTrip(templateID: nil, firstPlace: nil))
        window.navigator.sheet = nil
        window.findSpots()
        #expect(window.route == .find)
        #expect(window.navigator.searchFocusRequest == 1)
        window.searchHere()
        #expect(window.navigator.searchHereRequest == 1)
        window.addSpot()
        #expect(window.navigator.addSpotRequest == 1)
        let trip = try #require(window.library.trips.first)
        window.navigator.open(.trip(trip.id))
        window.changeDates()
        #expect(window.navigator.sheet == .changeDates(tripID: trip.id))
        window.navigator.open(.place(UUID()))
        window.editPlace()
        if case .editPlace = window.navigator.sheet {} else { Issue.record("Edit Place did not ask for its sheet") }
    }

    @Test func newFolderMakesAFolderForTheCurrentSection() throws {
        let window = try makeWindow(seed: false)
        window.navigator.open(.allTrips)
        window.newFolder()
        guard case .tripFolder = window.route else { Issue.record("expected a trip folder, got \(window.route)"); return }
        window.navigator.open(.savedPlaces)
        window.newFolder()
        guard case .placeFolder = window.route else { Issue.record("expected a place folder, got \(window.route)"); return }
    }

    // MARK: Launch switches

    @Test func smokeSwitchParses() {
        #expect(SmokeSwitches(arguments: ["Iter", "-IterSmokeQuitAfter", "6"]).quitAfter == 6)
        #expect(SmokeSwitches(arguments: ["-IterSmokeQuitAfter", "0.5"]).quitAfter == 0.5)
        #expect(SmokeSwitches(arguments: ["-IterSmokeQuitAfter"]).quitAfter == nil)
        #expect(SmokeSwitches(arguments: ["-IterSmokeQuitAfter", "soon"]).quitAfter == nil)
        #expect(SmokeSwitches(arguments: ["-IterSmokeQuitAfter", "-3"]).quitAfter == nil)
        #expect(SmokeSwitches(arguments: []).quitAfter == nil)
    }

    @Test func smokeReadyLineHasTheContractShape() {
        #expect(SmokeRun.readyLine(trips: 3, stops: 9, route: "trip") == "smoke: ready trips=3 stops=9 route=trip")
    }

    // MARK: Import and export

    @Test func importMergesAndReportsASummary() throws {
        let source = try makeWindow(seed: true)
        let file = try source.library.exportLibrary()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Shell Import \(UUID().uuidString).iter")
        try file.data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let target = try makeWindow(seed: false)
        #expect(target.library.trips.isEmpty)
        target.chooseImport(.success(url))
        let pending = try #require(target.pendingImport)
        target.performImport(pending, asCopy: false)
        #expect(target.pendingImport == nil)
        guard case .imported(let text) = target.notice else { Issue.record("expected a summary, got \(String(describing: target.notice))"); return }
        #expect(text.hasPrefix("Added 3 trips"))
        #expect(target.library.trips.count == 3)

        // The same file again changes nothing.
        target.chooseImport(.success(url))
        target.performImport(try #require(target.pendingImport), asCopy: false)
        guard case .imported(let again) = target.notice else { Issue.record("expected a summary"); return }
        #expect(again.contains("already in your library"))
    }

    @Test func importAsCopyAddsNewTrips() throws {
        let window = try makeWindow(seed: true)
        let before = window.library.trips.count
        let file = try window.library.exportLibrary()
        window.performImport(PendingImport(name: "Copy", data: file.data), asCopy: true)
        #expect(window.library.trips.count == before * 2)
        guard case .imported(let text) = window.notice else { Issue.record("expected a summary"); return }
        #expect(text.contains("new copies"))
    }

    @Test func unreadableFileGivesTheImportErrorAlert() throws {
        let window = try makeWindow(seed: false)
        window.performImport(PendingImport(name: "Junk", data: Data("not an iter file".utf8)), asCopy: false)
        guard let notice = window.notice else { Issue.record("expected an alert"); return }
        #expect(notice.title == "Couldn't Import Trip")
        #expect(window.library.trips.isEmpty)
    }

    @Test func exportBuildsADocumentNamedAfterTheTrip() throws {
        let window = try makeWindow(seed: true)
        let trip = try #require(window.library.trips.first)
        window.navigator.open(.trip(trip.id))
        window.exportCurrentTrip()
        #expect(window.showsExporter)
        #expect(window.exportDocument?.data.isEmpty == false)
        #expect(window.exportName.contains(trip.name.prefix(5)))
        window.showsExporter = false
        window.exportLibrary()
        #expect(window.exportName == "Iter Library")
    }

    // MARK: Debug actions

    @Test func debugResetAndSeedWorkOnTheInMemoryStore() throws {
        let window = try makeWindow(seed: true)
        #expect(!window.library.trips.isEmpty)
        window.resetAllData()
        #expect(window.library.trips.isEmpty)
        #expect(window.route == .allTrips)
        window.seedSampleTrip()
        guard case .trip = window.route else { Issue.record("expected the seeded trip to open"); return }
        #expect(!window.library.trips.isEmpty)
        #expect(window.notice == nil)
    }

    @Test func debugRefusalTextNamesTheRealLibrary() {
        #expect(WindowShell.debugReason(DebugActionError.refusedOnRealStore).contains("real library"))
    }

    // MARK: Helpers

    func makeWindow(seed: Bool) throws -> WindowShell {
        WindowShell(shell: try makeShell(seed: seed))
    }
}

@MainActor
func makeShell(seed: Bool) throws -> AppShell {
    let defaults = UserDefaults(suiteName: "iter.shell.tests.\(UUID().uuidString)")!
    let updates = UpdateController(updater: nil, defaults: defaults, presentsWindow: false)
    return AppShell(container: try AppContainer.test(seed: seed), smoke: SmokeSwitches(arguments: []), updates: updates)
}
