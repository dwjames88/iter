import Testing
import Foundation
@testable import IterLicensing

@Suite("LicenseManager")
struct LicenseManagerTests {
    final class Server: @unchecked Sendable {
        private let lock = NSLock()
        private var _validate: (Int, Data) = (200, Fixtures.validateOK)
        private var _offline = false
        func setValidate(_ status: Int, _ data: Data) { lock.withLock { _validate = (status, data) } }
        func setOffline(_ v: Bool) { lock.withLock { _offline = v } }
        func answer(_ path: String) throws -> (Int, [String: String], Data) {
            let (offline, validate) = lock.withLock { (_offline, _validate) }
            if offline { throw URLError(.notConnectedToInternet) }
            switch path {
            case "/v1/licenses/activate": return (200, [:], Fixtures.activateOK)
            case "/v1/licenses/deactivate": return (200, [:], Fixtures.deactivateOK)
            default: return (validate.0, [:], validate.1)
            }
        }
    }

    struct Rig {
        let manager: LicenseManager
        let clock: TestClock
        let server: Server
        let storage: InMemoryLicenseStorage
    }

    func rig() -> Rig {
        let server = Server()
        let storage = InMemoryLicenseStorage()
        let clock = TestClock(Date(timeIntervalSince1970: 1_800_000_000))
        let session = makeSession { request, _ in try server.answer(request.url!.path()) }
        let client = LicenseClient(configuration: .init(baseURL: URL(string: "https://example.test")!), session: session)
        let manager = LicenseManager(client: client, store: LicenseStore(storage: storage), clock: { clock.now })
        return Rig(manager: manager, clock: clock, server: server, storage: storage)
    }

    @Test func activateMakesLicensed() async throws {
        let r = rig()
        let state = try await r.manager.activate(key: " 38b1460a51044067a91d77b872934d51 ", instanceName: "Mac")
        #expect(state == .licensed(email: "john@example.com", activatedAt: Date(timeIntervalSince1970: 1_617_718_507)))
    }

    @Test func malformedKeyThrows() async {
        await #expect(throws: LicenseError.malformedKey) {
            try await rig().manager.activate(key: "nope", instanceName: "Mac")
        }
    }

    @Test func withinGraceOfflineStaysLicensed() async throws {
        let r = rig()
        try await r.manager.activate(key: Fixtures.key, instanceName: "Mac")
        r.server.setOffline(true)
        r.clock.advance(days: 13)
        let state = try await r.manager.validate()
        guard case .licensed = state else { Issue.record("expected licensed, got \(state)"); return }
    }

    @Test func beyondGraceOfflineIsExpiredNotRevoked() async throws {
        let r = rig()
        try await r.manager.activate(key: Fixtures.key, instanceName: "Mac")
        r.server.setOffline(true)
        r.clock.advance(days: 15)
        #expect(try await r.manager.validate() == .expired)
    }

    @Test func successfulValidateRestartsGrace() async throws {
        let r = rig()
        try await r.manager.activate(key: Fixtures.key, instanceName: "Mac")
        r.clock.advance(days: 20)
        #expect(try await r.manager.currentState() == .expired)
        let state = try await r.manager.validate()
        guard case .licensed = state else { Issue.record("expected licensed, got \(state)"); return }
    }

    @Test func tamperedLastValidatedInvalidatesToken() async throws {
        let r = rig()
        try await r.manager.activate(key: Fixtures.key, instanceName: "Mac")
        let store = LicenseStore(storage: r.storage)
        var license = try #require(try store.load()).license
        license.lastValidated = license.lastValidated.addingTimeInterval(10 * 86_400) // pretend validated later
        try r.storage.saveRecord(JSONEncoder().encode(license))
        #expect(try await r.manager.currentState(now: r.clock.now) == .expired)
    }

    @Test func clockSkewBackwardsSmallToleratedLargeExpires() async throws {
        let r = rig()
        try await r.manager.activate(key: Fixtures.key, instanceName: "Mac")
        let start = r.clock.now
        let small = try await r.manager.currentState(now: start.addingTimeInterval(-3_600))
        guard case .licensed = small else { Issue.record("small skew should be tolerated"); return }
        #expect(try await r.manager.currentState(now: start.addingTimeInterval(-2 * 86_400)) == .expired)
        // A successful validate with the (wrong) current clock clears the suspicion.
        r.clock.set(start.addingTimeInterval(-2 * 86_400))
        let state = try await r.manager.validate()
        guard case .licensed = state else { Issue.record("expected licensed after revalidation, got \(state)"); return }
    }

    @Test func disabledKeyIsRevokedAndCleared() async throws {
        let r = rig()
        try await r.manager.activate(key: Fixtures.key, instanceName: "Mac")
        r.server.setValidate(400, Fixtures.validateDisabled)
        #expect(try await r.manager.validate() == .revoked)
        #expect(try LicenseStore(storage: r.storage).load() == nil)
        #expect(try await r.manager.currentState() == .revoked)
    }

    @Test func notFoundIsRevoked() async throws {
        let r = rig()
        try await r.manager.activate(key: Fixtures.key, instanceName: "Mac")
        r.server.setValidate(404, Fixtures.notFound)
        #expect(try await r.manager.validate() == .revoked)
    }

    @Test func rateLimitedValidateKeepsState() async throws {
        let r = rig()
        try await r.manager.activate(key: Fixtures.key, instanceName: "Mac")
        r.server.setValidate(429, Data())
        let state = try await r.manager.validate()
        guard case .licensed = state else { Issue.record("expected licensed, got \(state)"); return }
    }

    @Test func deactivateClears() async throws {
        let r = rig()
        try await r.manager.activate(key: Fixtures.key, instanceName: "Mac")
        try await r.manager.deactivate()
        #expect(try await r.manager.currentState() == .unlicensed)
    }

    @Test func deactivateOfflineThrowsAndKeepsKey() async throws {
        let r = rig()
        try await r.manager.activate(key: Fixtures.key, instanceName: "Mac")
        r.server.setOffline(true)
        await #expect(throws: LicenseError.network(.notConnectedToInternet)) { try await r.manager.deactivate() }
        let state = try await r.manager.currentState()
        guard case .licensed = state else { Issue.record("expected licensed, got \(state)"); return }
    }

    @Test func trialCountsDownAndExpires() async throws {
        let r = rig()
        #expect(try await r.manager.currentState() == .unlicensed)
        try await r.manager.startTrialIfNeeded()
        #expect(try await r.manager.currentState() == .trial(daysLeft: 14))
        r.clock.advance(days: 0.5)
        #expect(try await r.manager.currentState() == .trial(daysLeft: 14))
        r.clock.advance(days: 1)
        #expect(try await r.manager.currentState() == .trial(daysLeft: 13))
        r.clock.advance(days: 12)
        #expect(try await r.manager.currentState() == .trial(daysLeft: 1))
        r.clock.advance(days: 1)
        #expect(try await r.manager.currentState() == .expired)
    }

    @Test func trialMath() {
        let start = Date(timeIntervalSince1970: 0)
        #expect(LicenseState.trial(startedAt: start, now: start) == .trial(daysLeft: 14))
        #expect(LicenseState.trial(startedAt: start, now: start.addingTimeInterval(13.5 * 86_400)) == .trial(daysLeft: 1))
        #expect(LicenseState.trial(startedAt: start, now: start.addingTimeInterval(14 * 86_400)) == .expired)
        #expect(LicenseState.trial(startedAt: start, now: start.addingTimeInterval(-3_600)) == .trial(daysLeft: 14))
        #expect(LicenseState.trial(startedAt: start, now: start.addingTimeInterval(-3 * 86_400)) == .expired)
    }

    @Test func startTrialDoesNotRestart() async throws {
        let r = rig()
        try await r.manager.startTrialIfNeeded()
        r.clock.advance(days: 5)
        try await r.manager.startTrialIfNeeded()
        #expect(try await r.manager.currentState() == .trial(daysLeft: 9))
    }
}
