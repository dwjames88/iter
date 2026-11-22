import Testing
import Foundation
@testable import IterLicensing

@Suite("Licence settings")
struct LicenceTextTests {
    @Test func everyErrorHasAShortHumanSentence() {
        let errors: [LicenseError] = [
            .malformedKey, .invalidKey, .keyDisabled, .keyExpired, .activationLimitReached,
            .rateLimited(retryAfter: nil), .rateLimited(retryAfter: 30), .badRequest("The license_key field is required."), .badRequest(""),
            .network(.notConnectedToInternet), .server(500), .decoding, .productMismatch,
        ]
        for error in errors {
            let text = LicenceText.message(for: error)
            #expect(text.hasSuffix("."), "\(error)")
            #expect(!text.contains("LicenseError"), "\(error)")
        }
    }

    @Test func limitMessageSaysHowToFreeAMac() {
        let text = LicenceText.message(for: LicenseError.activationLimitReached)
        #expect(text.contains("Deactivate This Mac"))
    }

    @Test func rateLimitMentionsTheWait() {
        #expect(LicenceText.message(for: LicenseError.rateLimited(retryAfter: 12)).contains("12 seconds"))
        #expect(LicenceText.message(for: LicenseError.rateLimited(retryAfter: nil)).contains("a minute"))
    }

    @Test func offlineAndNotFoundAreDistinct() {
        #expect(LicenceText.message(for: LicenseError.network(.timedOut)).contains("couldn't reach"))
        #expect(LicenceText.message(for: LicenseError.invalidKey).contains("wasn't found"))
    }

    @Test func otherErrorsGetAGenericSentence() {
        #expect(LicenceText.message(for: KeychainError(status: -25300)).contains("Keychain"))
    }

    @Test func stateStrings() {
        #expect(LicenceText.statusTitle(.unlicensed) == "Not licensed")
        #expect(LicenceText.statusTitle(.licensed(email: nil, activatedAt: Date())) == "Licensed")
        #expect(LicenceText.statusTitle(.trial(daysLeft: 1)) == "Trial, 1 day left")
        #expect(LicenceText.statusTitle(.trial(daysLeft: 9)) == "Trial, 9 days left")
        #expect(LicenceText.statusTitle(.expired) == "Needs a check")
        #expect(LicenceText.statusTitle(.revoked) == "Key no longer valid")
        #expect(LicenceText.statusDetail(.unlicensed) == nil)
        #expect(LicenceText.statusDetail(.licensed(email: "a@b.co", activatedAt: Date())) == "Licensed to a@b.co.")
        #expect(LicenceText.statusDetail(.licensed(email: nil, activatedAt: Date())) == nil)
        #expect(LicenceText.statusDetail(.revoked)?.contains("different key") == true)
        #expect(LicenceText.statusDetail(.expired)?.contains("Check Now") == true)
    }

    @Test func activateLinkFollowsTheSiteOrigin() {
        #expect(LicenceSetup.activateURL.path() == "/activate")
        #expect(LicenceSetup.activateURL.host() == LicenceSetup.siteOrigin.host())
    }
}

@MainActor
@Suite("LicenceSettingsModel")
struct LicenceSettingsModelTests {
    func model(status: Int = 200, body: Data = Fixtures.activateOK, offline: Bool = false) -> (LicenceSettingsModel, InMemoryLicenseStorage) {
        let storage = InMemoryLicenseStorage()
        let session = makeSession { request, _ in
            if offline { throw URLError(.notConnectedToInternet) }
            switch request.url!.path() {
            case "/v1/licenses/activate": return (status, [:], body)
            case "/v1/licenses/deactivate": return (200, [:], Fixtures.deactivateOK)
            default: return (200, [:], Fixtures.validateOK)
            }
        }
        let client = LicenseClient(configuration: .init(baseURL: URL(string: "https://example.test")!), session: session)
        let store = LicenseStore(storage: storage)
        return (LicenceSettingsModel(manager: LicenseManager(client: client, store: store), store: store, suggestedName: "Test"), storage)
    }

    @Test func startsUnlicensedWithoutATrial() async {
        let (m, storage) = model()
        await m.refresh()
        #expect(m.state == .unlicensed)
        #expect(m.maskedKey == nil)
        #expect((try? LicenseStore(storage: storage).trialStart()) == nil)
    }

    @Test func activateEnablesOnlyForAWellFormedKey() {
        let (m, _) = model()
        m.keyInput = "nope"
        #expect(!m.canActivate)
        m.keyInput = " 38b1460a-5104-4067-a91d-77b872934d51 "
        #expect(m.canActivate)
    }

    @Test func activateThenDeactivate() async {
        let (m, _) = model()
        m.keyInput = Fixtures.key
        await m.activate()
        #expect(m.isLicensed)
        #expect(m.email == "john@example.com")
        #expect(m.maskedKey?.hasSuffix("4D51") == true)
        #expect(m.instanceName == "Test")
        #expect(m.keyInput.isEmpty)
        #expect(m.errorMessage == nil)
        await m.deactivate()
        #expect(m.state == .unlicensed)
        #expect(m.maskedKey == nil)
    }

    @Test func limitReachedShowsTheMessageAndStaysUnlicensed() async {
        let (m, _) = model(status: 400, body: Fixtures.activateLimit)
        m.keyInput = Fixtures.key
        await m.activate()
        #expect(m.state == .unlicensed)
        #expect(m.errorMessage == LicenceText.message(for: LicenseError.activationLimitReached))
        #expect(!m.isBusy)
    }

    @Test func offlineActivateExplainsAndKeepsTheKeyField() async {
        let (m, _) = model(offline: true)
        m.keyInput = Fixtures.key
        await m.activate()
        #expect(m.errorMessage?.contains("couldn't reach") == true)
        #expect(!m.keyInput.isEmpty)
    }

    @Test func validateWithoutAKeyChangesNothing() async {
        let (m, _) = model()
        await m.validate()
        #expect(m.state == .unlicensed)
        #expect(m.errorMessage == nil)
    }
}
