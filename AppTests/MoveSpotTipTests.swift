import Testing
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
