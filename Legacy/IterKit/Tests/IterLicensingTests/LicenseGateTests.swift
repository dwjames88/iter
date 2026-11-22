import Testing
import Foundation
@testable import IterLicensing

@Suite("LicenseGate and InstanceName")
struct LicenseGateTests {
    let licensed = LicenseState.licensed(email: nil, activatedAt: .now)

    @Test func noOpWhenNotEnforced() {
        let gate = LicenseGate(isEnforced: false)
        for state in [LicenseState.unlicensed, .expired, .revoked, .trial(daysLeft: 1), licensed] {
            for feature in ProFeature.allCases { #expect(gate.allows(feature, state: state)) }
        }
    }

    @Test func gatesWhenEnforced() {
        let gate = LicenseGate(isEnforced: true)
        for feature in ProFeature.allCases {
            #expect(gate.allows(feature, state: licensed))
            #expect(gate.allows(feature, state: .trial(daysLeft: 3)))
            #expect(!gate.allows(feature, state: .unlicensed))
            #expect(!gate.allows(feature, state: .expired))
            #expect(!gate.allows(feature, state: .revoked))
        }
    }

    @Test func parsesInfoPlistValues() {
        #expect(LicenseGate.parseEnforced(true))
        #expect(LicenseGate.parseEnforced("YES"))
        #expect(LicenseGate.parseEnforced("true"))
        #expect(!LicenseGate.parseEnforced("NO"))
        #expect(!LicenseGate.parseEnforced("$(ITER_LICENSING_ENFORCED)"))
        #expect(!LicenseGate.parseEnforced(nil))
    }

    @Test func currentDefaultsToNotEnforcedInTests() {
        #expect(!LicenseGate.current.isEnforced)
    }

    @Test func instanceNameFormat() {
        #expect(InstanceName.format(model: "Mac15,3", user: "Dan") == "Mac15,3 \u{2013} Dan")
        #expect(InstanceName.format(model: "Mac15,3", user: "  ") == "Mac15,3")
        #expect(InstanceName.make(userChosen: "Studio Mac").hasSuffix("\u{2013} Studio Mac"))
        #expect(!InstanceName.hardwareModel().isEmpty)
    }
}
