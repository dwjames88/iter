import Foundation
import SwiftUI
import Testing
import IterFeatures
import IterModel
@testable import Iter

@MainActor
func makeTestShell(seedTrip: Bool = true) throws -> IOSShell {
    let options = LaunchOptions(inMemoryStore: true, sampleData: true, fixedLocation: Coordinate(latitude: 37.7749, longitude: -122.4194),
                                seedTrip: seedTrip)
    let container = try AppContainer.live(options: options, bundleID: "com.dwjames.iter.render", environment: [:])
    return IOSShell(container: container)
}

@MainActor
@Suite struct ShellNavigationTests {
    @Test func everyRouteLandsOnTheRightTabAndPath() throws {
        let shell = try makeTestShell()
        let id = UUID()
        shell.show(.find); #expect(shell.tab == .find)
        shell.show(.allTrips); #expect(shell.tab == .trips && shell.tripsPath.isEmpty)
        shell.show(.trip(id)); #expect(shell.tab == .trips && shell.tripsPath == [.trip(id)])
        shell.show(.tripFolder(id)); #expect(shell.tab == .trips && shell.tripsPath == [.tripFolder(id)])
        shell.show(.savedPlaces); #expect(shell.tab == .saved && shell.savedPath.isEmpty)
        shell.show(.placeFolder(id)); #expect(shell.tab == .saved && shell.savedPath == [.placeFolder(id)])
        shell.show(.place(id)); #expect(shell.tab == .saved && shell.savedPath == [.place(id)])
    }

    @Test func showClosesSettings() throws {
        let shell = try makeTestShell()
        shell.showsSettings = true
        shell.show(.find)
        #expect(!shell.showsSettings)
    }

    @Test func openTripIDIsTheLastTripInTheTripsPath() throws {
        let shell = try makeTestShell()
        let a = UUID(), b = UUID()
        #expect(shell.openTripID == nil)
        shell.tripsPath = [.tripFolder(a)]
        #expect(shell.openTripID == nil)
        shell.tripsPath = [.trip(a), .place(b)]
        #expect(shell.openTripID == a)
    }

    @Test func buildModelIsCachedPerTrip() throws {
        let shell = try makeTestShell()
        let trip = try #require(shell.library.trips.first)
        #expect(shell.buildModel(for: trip.id) === shell.buildModel(for: trip.id))
    }

    @Test func padSelectionDrivesTheRouteAndGoAndSettings() throws {
        let shell = try makeTestShell()
        shell.padSelection = .go
        #expect(shell.tab == .go && shell.padSelection == .go)
        shell.padSelection = .settings
        #expect(shell.padSelection == .settings)
        shell.padSelection = .app(.savedPlaces)
        #expect(shell.navigator.route == .savedPlaces && shell.tab == .saved && shell.padSelection == .app(.savedPlaces))
    }
}

@MainActor
@Suite struct ShellLinkTests {
    let file = URL(fileURLWithPath: "/tmp/a.iter")
    let goLink = URL(string: "iter://go/start")!

    @Test func sharingIsAskedFirstThenGo() {
        var order: [String] = []
        let outcome = IOSShell.dispatch(file, sharing: { _ in order.append("sharing"); return true }, go: { _ in order.append("go"); return true })
        #expect(outcome == .sharing && order == ["sharing"])
        order = []
        let go = IOSShell.dispatch(goLink, sharing: { _ in order.append("sharing"); return false }, go: { _ in order.append("go"); return true })
        #expect(go == .go && order == ["sharing", "go"])
        #expect(IOSShell.dispatch(goLink, sharing: { _ in false }, go: { _ in false }) == .unhandled)
    }
}

@Suite struct LaunchSwitchTests {
    @Test func parsesTheShellSwitches() {
        let s = IOSLaunchSwitches(arguments: ["Iter", "-IterSection", "trips", "-IterTab", "saved", "-IterSheetDetent", "full", "-IterOpenPlace", "first"])
        #expect(s.section == "trips" && s.tab == .saved && s.detent == PhoneSheet.full && s.openFirstPlace)
        let none = IOSLaunchSwitches(arguments: ["Iter"])
        #expect(none == IOSLaunchSwitches())
        #expect(IOSLaunchSwitches(arguments: ["-IterSheetDetent", "peek"]).detent == PhoneSheet.peek)
        #expect(IOSLaunchSwitches(arguments: ["-IterTab", "nonsense"]).tab == nil)
    }

    @Test func sectionsMapToRoutes() {
        let id = UUID()
        #expect(IOSLaunchSwitches.route(forSection: "find", firstTripID: id) == .find)
        #expect(IOSLaunchSwitches.route(forSection: "trips", firstTripID: id) == .allTrips)
        #expect(IOSLaunchSwitches.route(forSection: "places", firstTripID: id) == .savedPlaces)
        #expect(IOSLaunchSwitches.route(forSection: "trip", firstTripID: id) == .trip(id))
        #expect(IOSLaunchSwitches.route(forSection: "trip", firstTripID: nil) == .allTrips)
        #expect(IOSLaunchSwitches.route(forSection: nil, firstTripID: id) == nil)
    }

    @MainActor @Test func applyOpensTheFirstTripAndPlace() throws {
        let shell = try makeTestShell()
        shell.apply(IOSLaunchSwitches(section: "trip"))
        #expect(shell.tab == .trips && shell.openTripID != nil)
        shell.apply(IOSLaunchSwitches(tab: .go, detent: PhoneSheet.peek))
        #expect(shell.tab == .go && shell.detent == PhoneSheet.peek)
        shell.apply(IOSLaunchSwitches(openFirstPlace: true))
        if let place = shell.library.savedPlaces.first { #expect(shell.savedPath == [.place(place.id)] && shell.tab == .saved) }
    }

    @Test func phoneOrPad() {
        #expect(ShellLayout.resolve(isPad: false, horizontalSizeClass: .regular) == .phone)
        #expect(ShellLayout.resolve(isPad: true, horizontalSizeClass: .regular) == .pad)
        #expect(ShellLayout.resolve(isPad: true, horizontalSizeClass: .compact) == .phone)
        #expect(ShellLayout.resolve(isPad: true, horizontalSizeClass: nil) == .phone)
    }

    @MainActor @Test func aFailingStoreShowsTheFailureScreenNotACrash() {
        struct Boom: Error {}
        let result = IOSLaunch.launch(makeContainer: { throw Boom() })
        guard case .failed(let failure) = result else { Issue.record("expected failure"); return }
        #expect(failure.message.contains("Nothing was changed") && !failure.message.contains("Finder"))
    }
}
