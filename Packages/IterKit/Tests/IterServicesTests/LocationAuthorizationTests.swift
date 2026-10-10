import Testing
import CoreLocation
@testable import IterServices

/// `.authorizedWhenInUse` is unavailable on macOS; its raw value is 4.
private let whenInUse = CLAuthorizationStatus(rawValue: 4)!

@MainActor
@Suite struct LocationAuthorizationTests {
    @Test func statusMapping() {
        #expect(CoreLocationProvider.map(.authorizedAlways) == .authorized)
        #expect(CoreLocationProvider.map(whenInUse) == .authorized)
        #expect(CoreLocationProvider.map(.denied) == .denied)
        #expect(CoreLocationProvider.map(.restricted) == .restricted)
        #expect(CoreLocationProvider.map(.notDetermined) == .notDetermined)
    }

    @Test func alwaysUpgradeTruthTable() {
        let all: [CLAuthorizationStatus] = [.notDetermined, .restricted, .denied, .authorizedAlways, whenInUse]
        for status in all {
            for asked in [false, true] {
                for supports in [false, true] {
                    let expected = status == whenInUse && !asked && supports
                    #expect(CoreLocationProvider.shouldRequestAlwaysUpgrade(status: status, alreadyAsked: asked, supportsAlways: supports) == expected)
                }
            }
        }
    }
}
