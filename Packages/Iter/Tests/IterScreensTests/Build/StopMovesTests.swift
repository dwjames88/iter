import Foundation
import Testing
@testable import IterScreens

@Suite struct StopMovesTests {
    let a = UUID(), b = UUID(), c = UUID(), d = UUID()
    var days: [Int: [UUID]] { [0: [a, b, c], 1: [d]] }

    @Test func dropBeforeEarlierStopInSameDay() {
        let move = StopMoves.destination(of: c, dropping: .before(a), dayStops: days)
        #expect(move?.day == 0 && move?.index == 0)
    }

    @Test func dropBeforeLaterStopInSameDayIndexIgnoresTheMovingStop() {
        // [a, b, c]: a before c leaves [b, c] and c is at index 1.
        let move = StopMoves.destination(of: a, dropping: .before(c), dayStops: days)
        #expect(move?.day == 0 && move?.index == 1)
    }

    @Test func dropBeforeTheStopThatAlreadyFollowsIsNoOp() {
        #expect(StopMoves.destination(of: a, dropping: .before(b), dayStops: days) == nil)
    }

    @Test func dropOnSelfIsNoOp() {
        #expect(StopMoves.destination(of: b, dropping: .before(b), dayStops: days) == nil)
    }

    @Test func dropAcrossDays() {
        let move = StopMoves.destination(of: a, dropping: .before(d), dayStops: days)
        #expect(move?.day == 1 && move?.index == 0)
    }

    @Test func dropOnDayFootAppendsUnlessAlreadyLast() {
        #expect(StopMoves.destination(of: a, dropping: .endOfDay(1), dayStops: days)?.day == 1)
        #expect(StopMoves.destination(of: a, dropping: .endOfDay(1), dayStops: days)?.index == nil)
        #expect(StopMoves.destination(of: c, dropping: .endOfDay(0), dayStops: days) == nil)
    }

    @Test func moveUpAndDown() {
        #expect(StopMoves.up(a, dayStops: days) == nil)
        #expect(StopMoves.up(c, dayStops: days)?.index == 1)
        #expect(StopMoves.down(c, dayStops: days) == nil)
        #expect(StopMoves.down(a, dayStops: days)?.index == 1)
        #expect(StopMoves.down(d, dayStops: days) == nil)
    }

    @Test func routeCameraCapsTheSpan() {
        import_check()
    }

    private func import_check() {
        let region = RouteCamera.region(.init(center: .init(latitude: 0, longitude: 0), latitudeDelta: 90, longitudeDelta: 120))
        #expect(region.span.latitudeDelta == 40 && region.span.longitudeDelta == 40)
    }
}
