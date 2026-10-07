import Foundation
import Testing
@testable import IterFeatures

@Suite struct MapStyleChoiceTests {
    private func defaults() -> UserDefaults {
        let name = "MapStyleChoiceTests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    @Test func standardIsTheDefault() {
        #expect(MapStyleChoice.current(in: defaults()) == .standard)
        #expect(MapStyleChoice(stored: nil) == .standard)
        #expect(MapStyleChoice(stored: "nonsense") == .standard)
    }

    @Test func theChoiceRoundTripsThroughTheOneKey() {
        let d = defaults()
        for choice in MapStyleChoice.allCases {
            choice.save(in: d)
            #expect(d.string(forKey: "iter.map.style") == choice.rawValue)
            #expect(MapStyleChoice.current(in: d) == choice)
        }
        #expect(MapStyleChoice.allCases == [.standard, .satellite, .hybrid])
    }
}
