import Testing
import Foundation
import IterCore
import IterServices
@testable import IterFeatures

@MainActor
private final class FakeLocation: UserLocationProviding {
    var authorization: LocationAuthorization
    var fix: Coordinate?
    var authorizationRequests = 0
    var fixRequests = 0
    var onAuthorizationChange: (@MainActor (LocationAuthorization) -> Void)?
    init(_ authorization: LocationAuthorization, fix: Coordinate? = nil) { self.authorization = authorization; self.fix = fix }
    func requestAuthorization() { authorizationRequests += 1 }
    func requestFix() async -> Coordinate? { fixRequests += 1; return fix }
}

private func suite() -> UserDefaults {
    let d = UserDefaults(suiteName: "UserLocationTests-\(UUID().uuidString)")!
    return d
}

private let sf = Coordinate(latitude: 37.7749, longitude: -122.4194)
private let la = Coordinate(latitude: 34.0522, longitude: -118.2437)
private let monterey = Coordinate(latitude: 36.6, longitude: -121.9)

@MainActor
private func settle() async { for _ in 0..<20 { await Task.yield() } }

@MainActor
@Suite struct UserLocationModelTests {
    @Test func notDeterminedRequestsAuthorizationOnce() async {
        let fake = FakeLocation(.notDetermined)
        let model = UserLocationModel(provider: fake, defaults: suite())
        model.start()
        #expect(fake.authorizationRequests == 1)
        #expect(model.coordinate == nil)
        // Granting triggers a fix.
        fake.authorization = .authorized; fake.fix = sf
        fake.onAuthorizationChange?(.authorized)
        await settle()
        #expect(model.coordinate == sf)
    }

    @Test func cachedFixShownThenReplacedAndPersisted() async {
        let defaults = suite()
        defaults.set(["lat": la.latitude, "lon": la.longitude, "timestamp": 1.0], forKey: UserLocationModel.lastFixKey)
        let fake = FakeLocation(.authorized, fix: sf)
        let model = UserLocationModel(provider: fake, defaults: defaults)
        model.start()
        #expect(model.coordinate == la)
        #expect(model.isLocating)
        await settle()
        #expect(model.coordinate == sf)
        #expect(!model.isLocating)
        let stored = defaults.dictionary(forKey: UserLocationModel.lastFixKey)
        #expect(stored?["lat"] as? Double == sf.latitude)
    }

    @Test func failedFixKeepsCache() async {
        let defaults = suite()
        defaults.set(["lat": la.latitude, "lon": la.longitude, "timestamp": 1.0], forKey: UserLocationModel.lastFixKey)
        let model = UserLocationModel(provider: FakeLocation(.authorized, fix: nil), defaults: defaults)
        model.start(); await settle()
        #expect(model.coordinate == la)
    }

    @Test func deniedIgnoresCache() async {
        let defaults = suite()
        defaults.set(["lat": la.latitude, "lon": la.longitude, "timestamp": 1.0], forKey: UserLocationModel.lastFixKey)
        let fake = FakeLocation(.denied, fix: sf)
        let model = UserLocationModel(provider: fake, defaults: defaults)
        model.start(); await settle()
        #expect(model.coordinate == nil)
        #expect(fake.fixRequests == 0)
        #expect(fake.authorizationRequests == 0)
    }

    @Test func radiusDefaultsAndPersists() {
        let defaults = suite()
        let model = UserLocationModel(provider: FakeLocation(.denied), defaults: defaults)
        #expect(model.radiusMiles == 300)
        model.radiusMiles = 500
        #expect(UserLocationModel(provider: FakeLocation(.denied), defaults: defaults).radiusMiles == 500)
        #expect(UserLocationModel.radiusChoices == [100, 200, 300, 500])
    }

    @Test func distanceSanFranciscoToLosAngeles() async {
        let model = UserLocationModel(provider: FakeLocation(.authorized, fix: sf), defaults: suite())
        #expect(model.distanceMiles(to: la) == nil)
        model.start(); await settle()
        let miles = model.distanceMiles(to: la)
        #expect(abs((miles ?? 0) - 347) < 2)
    }

    @Test func launchArgumentParsing() {
        #expect(UserLocationModel.parseLaunchLocation("36.6,-121.9") == monterey)
        #expect(UserLocationModel.parseLaunchLocation(" 36.6 , -121.9 ") == monterey)
        #expect(UserLocationModel.parseLaunchLocation(nil) == nil)
        #expect(UserLocationModel.parseLaunchLocation("") == nil)
        #expect(UserLocationModel.parseLaunchLocation("36.6") == nil)
        #expect(UserLocationModel.parseLaunchLocation("a,b") == nil)
        #expect(UserLocationModel.parseLaunchLocation("91,0") == nil)
        #expect(UserLocationModel.parseLaunchLocation("1,2,3") == nil)
    }

    @Test func fixedProviderIsSimulatedAndDoesNotPersist() async {
        let defaults = suite()
        let model = UserLocationModel(provider: FixedLocationProvider(monterey), isSimulated: true, defaults: defaults)
        model.start(); await settle()
        #expect(model.coordinate == monterey)
        #expect(model.isSimulated)
        #expect(defaults.dictionary(forKey: UserLocationModel.lastFixKey) == nil)
    }

    @Test func inertProviderNeverLocates() async {
        let model = UserLocationModel(defaults: suite())
        model.start(); await settle()
        #expect(model.authorization == .notDetermined)
        #expect(model.coordinate == nil)
    }

    @Test func requestAtLaunchAsksOnceAcrossRepeatedCalls() async {
        let fake = FakeLocation(.notDetermined)
        let model = UserLocationModel(provider: fake, defaults: suite())
        model.requestAtLaunch()
        model.requestAtLaunch()
        #expect(fake.authorizationRequests == 1)
        // The grant lands later: a fix follows with no further request.
        fake.authorization = .authorized; fake.fix = sf
        fake.onAuthorizationChange?(.authorized)
        await settle()
        #expect(model.coordinate == sf)
        #expect(fake.authorizationRequests == 1)
    }

    @Test func requestAtLaunchDoesNotAskWhenAlreadyDecided() async {
        let allowed = FakeLocation(.authorized, fix: sf)
        let allowedModel = UserLocationModel(provider: allowed, defaults: suite())
        allowedModel.requestAtLaunch(); allowedModel.requestAtLaunch(); await settle()
        #expect(allowed.authorizationRequests == 0)
        #expect(allowed.fixRequests == 1)
        #expect(allowedModel.coordinate == sf)
        let denied = FakeLocation(.denied)
        UserLocationModel(provider: denied, defaults: suite()).requestAtLaunch()
        #expect(denied.authorizationRequests == 0)
    }

    @Test func bannerStates() {
        typealias M = UserLocationModel
        #expect(M.bannerState(authorization: .notDetermined, isLocating: false, hasFix: false) == .none)
        #expect(M.bannerState(authorization: .denied, isLocating: false, hasFix: false) == .openSettings)
        #expect(M.bannerState(authorization: .restricted, isLocating: false, hasFix: false) == .openSettings)
        #expect(M.bannerState(authorization: .authorized, isLocating: true, hasFix: false) == .finding)
        #expect(M.bannerState(authorization: .authorized, isLocating: false, hasFix: false) == .unavailable)
        #expect(M.bannerState(authorization: .authorized, isLocating: false, hasFix: true) == .none)
        #expect(M.bannerState(authorization: .authorized, isLocating: true, hasFix: true) == .none)
    }

    @Test func bannerStateFollowsTheModel() async {
        let model = UserLocationModel(provider: FakeLocation(.notDetermined), defaults: suite())
        #expect(model.bannerState == .none)
        let fake = FakeLocation(.authorized, fix: sf)
        let allowed = UserLocationModel(provider: fake, defaults: suite())
        allowed.requestAtLaunch()
        #expect(allowed.bannerState == .finding)
        await settle()
        #expect(allowed.bannerState == .none)
    }

    @Test func renderCopyWithoutLaunchLocationNeverUsesCoreLocation() {
        let render = UserLocationModel.provider(launchLocation: nil, isRenderCopy: true)
        #expect(render.0 is InertLocationProvider)
        #expect(!render.simulated)
        let stub = UserLocationModel.provider(launchLocation: "37.77,-122.42", isRenderCopy: true)
        #expect(stub.0 is FixedLocationProvider)
        #expect(stub.simulated)
        #expect(UserLocationModel.provider(launchLocation: nil, isRenderCopy: false).0 is CoreLocationProvider)
    }
}
