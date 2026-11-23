import Foundation
import Testing
import IterGo
import IterModel
@testable import IterFeatures

@Suite struct GoWiringTests {
    private let real = StorePlacement.realBundleID

    @Test func realAppOnRealDataIsLive() {
        #expect(GoWiring.mode(bundleID: real, environment: [:], options: LaunchOptions()) == .live)
    }

    @Test func everythingElseGetsFakes() {
        let fixed = Coordinate(latitude: 1, longitude: 2)
        #expect(GoWiring.mode(bundleID: real, environment: ["XCTestConfigurationFilePath": "/x"], options: LaunchOptions()) == .fake(location: nil))
        #expect(GoWiring.mode(bundleID: "com.dwjames.iter.render", environment: [:], options: LaunchOptions()) == .fake(location: nil))
        #expect(GoWiring.mode(bundleID: real, environment: [:], options: LaunchOptions(sampleData: true)) == .fake(location: nil))
        #expect(GoWiring.mode(bundleID: real, environment: [:], options: LaunchOptions(fixedLocation: fixed)) == .fake(location: fixed))
        #expect(GoWiring.mode(bundleID: nil, environment: [:], options: LaunchOptions()) == .fake(location: nil))
    }

    @Test func sampleRunNeedsTheSwitchAndFakes() {
        let on = LaunchOptions(arguments: ["Iter", "-IterGoSampleRun", "YES"])
        #expect(GoWiring.wantsSampleRun(options: on, mode: .fake(location: nil)))
        #expect(!GoWiring.wantsSampleRun(options: on, mode: .live))
        #expect(!GoWiring.wantsSampleRun(options: LaunchOptions(arguments: ["Iter"]), mode: .fake(location: nil)))
        #expect(!GoWiring.wantsSampleRun(options: LaunchOptions(arguments: ["-IterGoSampleRun", "NO"]), mode: .fake(location: nil)))
    }

    @Test func parsesGoLinks() {
        let stop = UUID()
        #expect(GoLink.parse(URL(string: "iter://go")!) == .open)
        #expect(GoLink.parse(URL(string: "iter://go/")!) == .open)
        #expect(GoLink.parse(URL(string: "iter://go/navigate")!) == .navigate(stopID: nil))
        #expect(GoLink.parse(URL(string: "iter://go/navigate?stop=\(stop.uuidString)")!) == .navigate(stopID: stop))
        #expect(GoLink.parse(URL(string: "iter://go/navigate?stop=nope")!) == .navigate(stopID: nil))
        #expect(GoLink.parse(URL(string: "ITER://GO/Navigate")!) == .navigate(stopID: nil))
        #expect(GoLink.parse(URL(string: "iter://trips")!) == nil)
        #expect(GoLink.parse(URL(string: "https://go/navigate")!) == nil)
    }

    @Test func alwaysUpgradeIsClaimedOnce() throws {
        let suite = "go-always-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(!AlwaysUpgrade.hasAsked(in: defaults))
        #expect(AlwaysUpgrade.claim(in: defaults))
        #expect(!AlwaysUpgrade.claim(in: defaults))
        #expect(AlwaysUpgrade.hasAsked(in: defaults))
    }

    @MainActor @Test func fakeKitNeverAsksAndSendsFixes() async {
        let kit = GoFakeKit(position: Coordinate(latitude: 40, longitude: -110))
        #expect(kit.location.authorization == .always)
        #expect(await kit.notifications.authorization() == .authorized)
        kit.emitFix()
        var iterator = kit.location.events.makeAsyncIterator()
        if case .fix(let fix) = await iterator.next() { #expect(fix.coordinate.latitude == 40) } else { Issue.record("no fix") }
        #expect(kit.location.authorizationRequests.isEmpty)
        #expect(kit.notifications.calls.isEmpty)
    }
}
