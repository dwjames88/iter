import Testing
import IterFeatures
@testable import Iter

/// When the place card offers the "Move This Spot" tip.
struct MoveSpotTipTests {
    @Test func onlyYourOwnSpotsGetIt() {
        #expect(MoveSpotTip.isShown(canMove: true, renderMode: .live))
        #expect(!MoveSpotTip.isShown(canMove: false, renderMode: .live))
        #expect(!MoveSpotTip.isShown(canMove: false, renderMode: .live, forced: true))
    }

    @Test func snapshotsHideItUnlessTheyAsk() {
        #expect(!MoveSpotTip.isShown(canMove: true, renderMode: .snapshot))
        #expect(MoveSpotTip.isShown(canMove: true, renderMode: .snapshot, forced: true))
    }
}

/// The shared pin-drag modifier's seams on the Mac.
@MainActor struct OwnPinDragSeamTests {
    @Test func aViewKeepsOneDragModelAndTheMousePressRulesAreShared() {
        let model = Fixtures.model()
        let holder = OwnPinDragHolder()
        #expect(holder.model(for: model) === holder.model(for: model))
        // The pointer drags after 3 pt, with no hold; the pin rises 5 pt.
        #expect(PinDrag.pointerMinimumDistance == 3 && PinDrag.liftPoints == 5)
        // Only your own spots move: the saved catalogue ones do not.
        #expect(!holder.model(for: model).canMove("mesa-arch"))
    }
}
