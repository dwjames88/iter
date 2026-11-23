import Foundation
import SwiftUI
import Testing
import UserNotifications
import IterFeatures
import IterGo
import IterModel
import IterScreens
@testable import Iter

/// The Go controller on a sample container: fakes only, nothing prompts, posts or touches the system.
@MainActor
@Suite struct GoWiringHostedTests {
    static let renderBundle = "com.dwjames.iter.render"
    static let site = Coordinate(latitude: 36.8, longitude: -111.5)

    static func container() throws -> AppContainer {
        try AppContainer.live(options: LaunchOptions(inMemoryStore: true, sampleData: true, fixedLocation: site, seedTrip: true),
                              bundleID: renderBundle, environment: [:])
    }

    static func sampleTrip(_ shell: IOSShell) throws -> GoTripChoice {
        try #require(shell.go.trips.first { $0.name == "Canyon Country" })
    }

    static func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() { try? await Task.sleep(for: .milliseconds(25)) }
    }

    @Test func usesFakesAndStartsTheSampleTrip() async throws {
        let shell = IOSShell(container: try Self.container())
        let go = shell.go
        #expect(go.mode == .fake(location: Self.site))
        let kit = try #require(go.fakes)
        #expect(!go.isRunning)
        let trip = try Self.sampleTrip(shell)
        #expect(trip.stops.map(\.number) == Array(1...trip.stops.count))
        #expect(trip.stops.first?.dayIndex == 0)
        await go.start(tripID: trip.id, stopID: trip.stops.first?.id)
        #expect(go.isRunning)
        #expect(go.model.snapshot.tripID == trip.id)
        #expect(kit.location.authorizationRequests.isEmpty)
        #expect(!kit.notifications.calls.contains(.requestAuthorization))
        go.model.stop()
    }

    @Test func relaunchRestoresTheRun() async throws {
        let container = try Self.container()
        let shell = IOSShell(container: container)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("go-wiring-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = GoController(container: container, library: shell.library, bundleID: Self.renderBundle, environment: [:], fakeDirectory: directory)
        let trip = try Self.sampleTrip(shell)
        await first.start(tripID: trip.id, stopID: trip.stops.first?.id)
        #expect(first.isRunning)
        first.model.stop()

        let second = GoController(container: container, library: shell.library, bundleID: Self.renderBundle, environment: [:], fakeDirectory: directory)
        #expect(!second.isRunning)
        #expect(await second.restoreAtLaunch())
        #expect(second.isRunning)
        #expect(second.model.snapshot.tripID == trip.id)
        second.model.stop()
    }

    @Test func goLinksAreHandled() async throws {
        let shell = IOSShell(container: try Self.container())
        let go = shell.go
        #expect(go.handle(url: URL(string: "iter://go")!))
        #expect(!go.handle(url: URL(string: "iter://trips")!))
        #expect(!go.handle(url: URL(string: "https://example.com/go")!))
        // Not running: navigate is Go's but there is nowhere to go.
        #expect(go.handle(url: URL(string: "iter://go/navigate")!))
        let trip = try Self.sampleTrip(shell)
        await go.start(tripID: trip.id, stopID: trip.stops.first?.id)
        #expect(go.handle(url: URL(string: "iter://go/navigate")!))
        await Self.waitUntil { go.model.pendingNavigation != nil }
        #expect(go.model.pendingNavigation != nil)
        go.model.consumeNavigation()
        let later = try #require(trip.stops.last)
        #expect(go.handle(url: URL(string: "iter://go/navigate?stop=\(later.id.uuidString)")!))
        await Self.waitUntil { go.model.pendingNavigation != nil }
        #expect(go.model.pendingNavigation?.name == later.name)
        go.model.stop()
    }

    @Test func notificationActionsReachTheModelAndShowGo() async throws {
        let shell = IOSShell(container: try Self.container())
        let delegate = GoNotificationDelegate(shell: { shell })
        let trip = try Self.sampleTrip(shell)
        await shell.go.start(tripID: trip.id, stopID: trip.stops.first?.id)
        shell.tab = .find
        let stop = try #require(trip.stops.last)
        await delegate.handle(actionIdentifier: GoNotificationCategory.navigateAction, categoryIdentifier: GoNotificationCategory.navigate,
                              userInfo: ["stopID": stop.id.uuidString])
        #expect(shell.tab == .go)
        #expect(shell.go.model.pendingNavigation?.name == stop.name)
        // Other apps' notifications are not Go's.
        shell.tab = .find
        await delegate.handle(actionIdentifier: GoNotificationCategory.navigateAction, categoryIdentifier: "other", userInfo: [:])
        #expect(shell.tab == .find)
        // A plain tap shows Go and does nothing else.
        shell.go.model.consumeNavigation()
        await delegate.handle(actionIdentifier: UNNotificationDefaultActionIdentifier, categoryIdentifier: GoNotificationCategory.info, userInfo: [:])
        #expect(shell.tab == .go)
        #expect(shell.go.model.pendingNavigation == nil)
        shell.go.model.stop()
    }

    @Test func userInfoBecomesStrings() {
        let id = UUID()
        let info = GoNotificationDelegate.stringInfo(["stopID": id.uuidString, "n": 3, 4: "x"])
        #expect(info == ["stopID": id.uuidString])
    }

    @Test func backgroundIdentifierIsPermittedByThePlist() {
        // The real Info.plist lists it; a bundle without it registers nothing (BGTaskScheduler would raise).
        #expect(GoLaunchHooks.permittedIdentifiers(Bundle(for: IOSShell.self)).contains(GoBackground.refreshTaskIdentifier)
                || Bundle.main.bundleIdentifier != nil)
        #expect(GoLaunchHooks.isTestHost(["XCTestConfigurationFilePath": "x"]))
        #expect(!GoLaunchHooks.isTestHost([:]))
    }

    @Test func tripChoicesNumberStopsInDayOrder() throws {
        let shell = IOSShell(container: try Self.container())
        for choice in shell.go.trips {
            #expect(choice.stops.map(\.number) == Array(1...max(choice.stops.count, 1)).prefix(choice.stops.count).map { $0 })
            #expect(choice.stops.map(\.dayIndex) == choice.stops.map(\.dayIndex).sorted())
        }
    }

    @Test func sampleRunStartsOnLaunchWithFakes() async throws {
        var options = LaunchOptions(inMemoryStore: true, sampleData: true, seedTrip: true)
        options.arguments = ["Iter", "-IterGoSampleRun", "YES"]
        let container = try AppContainer.live(options: options, bundleID: Self.renderBundle, environment: [:])
        let shell = IOSShell(container: container)
        #expect(shell.go.fakes?.position != nil)
        #expect(await shell.go.restoreAtLaunch())
        #expect(shell.go.isRunning)
        shell.go.model.stop()
    }

    @Test func rendersAnActiveRun() async throws {
        var options = LaunchOptions(inMemoryStore: true, sampleData: true, seedTrip: true)
        options.arguments = ["Iter", "-IterGoSampleRun", "YES"]
        let container = try AppContainer.live(options: options, bundleID: Self.renderBundle, environment: [:])
        let shell = IOSShell(container: container)
        #expect(await shell.go.restoreAtLaunch())
        await Self.waitUntil { shell.go.model.snapshot.next != nil && shell.go.model.snapshot.leave?.leaveBy != nil }
        let images = try await GoHarness.render(NavigationStack { GoTabRoot(shell: shell) }
            .environment(\.goFlatButtons, true).environment(\.goClockMode, .frozen), name: "wired-go-active",
                                                size: CGSize(width: 402, height: 874))
        #expect(images.count == 2)
        for image in images { #expect(!GoHarness.isBlank(image)) }
        shell.go.model.stop()
    }
}
