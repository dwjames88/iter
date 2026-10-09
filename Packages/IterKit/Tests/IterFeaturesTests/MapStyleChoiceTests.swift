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

    @Test func hybridIsTheDefault() {
        #expect(MapStyleChoice.current(in: defaults()) == .hybrid)
        #expect(MapStyleChoice(stored: nil) == .hybrid)
        #expect(MapStyleChoice(stored: "nonsense") == .hybrid)
    }

    @Test func aSavedStandardChoiceBeatsTheDefault() {
        let d = defaults()
        MapStyleChoice.standard.save(in: d)
        #expect(MapStyleChoice.current(in: d) == .standard)
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
