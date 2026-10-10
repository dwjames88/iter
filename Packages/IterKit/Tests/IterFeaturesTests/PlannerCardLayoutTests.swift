import Testing
import CoreGraphics
@testable import IterFeatures

@Suite struct PlannerCardLayoutTests {
    /// A window with the 240 pt sidebar showing, as the app has it above about 1000 pt.
    private func layout(_ window: CGFloat, previous: PlannerCardLayout.Mode? = nil) -> PlannerCardLayout {
        PlannerCardLayout.resolve(windowWidth: window, detailWidth: window - 240, previous: previous)
    }

    @Test func modesAtTheThresholds() {
        #expect(layout(960).mode == .side)
        #expect(layout(1099).mode == .side)
        #expect(layout(1100).mode == .capped)
        #expect(layout(1280).mode == .capped)
        #expect(layout(1439).mode == .capped)
        #expect(layout(1440).mode == .wide)
        #expect(layout(1728).mode == .wide)
        #expect(layout(1800).mode == .wide)
    }

    @Test func wideCardKeepsTheCurrentWidths() {
        // 62 % of the detail area between 560 and 800.
        #expect(layout(1440).cardWidth == 1200 * 0.62)
        #expect(layout(1728).cardWidth == 800)
        #expect(layout(1800).cardWidth == 800)
        // The old centred card in a small detail area still leaves its margins.
        let tight = PlannerCardLayout.resolve(windowWidth: 1440, detailWidth: 500)
        #expect(tight.cardWidth == 484)
    }

    @Test func cappedCardLeavesFortyPercentOfTheWindowAsMap() {
        for window in stride(from: CGFloat(1100), to: 1440, by: 20) {
            let l = layout(window)
            let visibleMap = (window - 240) - l.cardWidth
            #expect(visibleMap >= 0.4 * window - 0.001, "window \(window)")
            #expect(l.cardWidth >= 340)
        }
        #expect(abs(layout(1280).cardWidth - (1040 - 512)) < 0.001)
        // Never wider than the wide card would be.
        #expect(layout(1439).cardWidth <= 1199 * 0.62 + 0.001)
    }

    @Test func sideCardIsTheListColumn() {
        // 960 pt: the map beside the card keeps its 420 pt minimum, so the card narrows to the list minimum.
        #expect(layout(960).cardWidth == 340)
        #expect(layout(1099).cardWidth == 360)
        // A window too narrow for the map beside it narrows the card to its minimum.
        let narrow = PlannerCardLayout.resolve(windowWidth: 761, detailWidth: 761)
        #expect(narrow.mode == .side)
        #expect(narrow.cardWidth == 340)
    }

    @Test func hysteresisHoldsAModeJustBelowItsThreshold() {
        // Growing through a threshold changes the mode at once.
        #expect(layout(1100, previous: .side).mode == .capped)
        #expect(layout(1440, previous: .capped).mode == .wide)
        // Shrinking holds the higher mode for a few points...
        #expect(layout(1099, previous: .capped).mode == .capped)
        #expect(layout(1093, previous: .capped).mode == .capped)
        #expect(layout(1439, previous: .wide).mode == .wide)
        #expect(layout(1433, previous: .wide).mode == .wide)
        // ...then lets go.
        #expect(layout(1091, previous: .capped).mode == .side)
        #expect(layout(1431, previous: .wide).mode == .capped)
        // The lower mode does not creep up early.
        #expect(layout(1099, previous: .side).mode == .side)
        #expect(layout(1439, previous: .capped).mode == .capped)
        // A big jump skips a mode.
        #expect(layout(1500, previous: .side).mode == .wide)
        #expect(layout(900, previous: .wide).mode == .side)
    }

    @Test func aSweepFlapsOncePerThresholdEachWay() {
        var mode: PlannerCardLayout.Mode?
        var changes = 0
        let widths = (1080...1460).map { CGFloat($0) } + (1080...1460).reversed().map { CGFloat($0) }
        for w in widths {
            let next = PlannerCardLayout.mode(windowWidth: w, previous: mode)
            if let mode, mode != next { changes += 1 }
            mode = next
        }
        #expect(changes == 4)
    }
}
