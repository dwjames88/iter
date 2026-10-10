import Testing
import IterFeatures
@testable import Iter

/// When the night-side overlay is drawn: far enough out, not stacked on MapKit's own globe night side, off when the user turns it off.
@MainActor
struct DaylightClockTests {
    private func clock(distance: Double) -> DaylightClock {
        let clock = DaylightClock()
        clock.cameraDistanceChanged(distance)
        return clock
    }

    @Test func regionalViewsNeverShowIt() {
        for style in MapStyleChoice.allCases {
            #expect(!clock(distance: 500_000).isShown(isOn: true, style: style))
        }
    }

    @Test func standardKeepsTheOverlayAtWorldZoomBecauseItNeverBecomesAGlobe() {
        #expect(clock(distance: 4_000_000).isShown(isOn: true, style: .standard))
        #expect(clock(distance: 45_000_000).isShown(isOn: true, style: .standard))
    }

    @Test func satelliteAndHybridHandOverToMapKitOnceTheGlobeAppears() {
        for style in [MapStyleChoice.satellite, .hybrid] {
            #expect(clock(distance: 4_000_000).isShown(isOn: true, style: style))
            #expect(!clock(distance: 45_000_000).isShown(isOn: true, style: style))
        }
    }

    @Test func theSettingTurnsItOff() {
        #expect(!clock(distance: 45_000_000).isShown(isOn: false, style: .standard))
    }

    @Test func zoomingBackInDropsIt() {
        let c = clock(distance: 45_000_000)
        c.cameraDistanceChanged(300_000)
        #expect(!c.isShown(isOn: true, style: .standard))
    }
}
