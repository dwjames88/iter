import Foundation
import Testing
@testable import Iter

/// The stop an arrow key selects in the Trip Builder list.
struct TripArrowKeyTests {
    private let ids = (0..<4).map { _ in UUID() }

    @Test func downAndUpWalkTripOrder() {
        #expect(TripPlanList.adjacentStop(in: ids, from: ids[1], step: 1) == ids[2])
        #expect(TripPlanList.adjacentStop(in: ids, from: ids[1], step: -1) == ids[0])
    }

    @Test func noSelectionStartsAtTheEnds() {
        #expect(TripPlanList.adjacentStop(in: ids, from: nil, step: 1) == ids[0])
        #expect(TripPlanList.adjacentStop(in: ids, from: nil, step: -1) == ids[3])
        #expect(TripPlanList.adjacentStop(in: ids, from: UUID(), step: 1) == ids[0])
    }

    @Test func staysPutAtTheEnds() {
        #expect(TripPlanList.adjacentStop(in: ids, from: ids[3], step: 1) == ids[3])
        #expect(TripPlanList.adjacentStop(in: ids, from: ids[0], step: -1) == ids[0])
    }

    @Test func emptyTripSelectsNothing() {
        #expect(TripPlanList.adjacentStop(in: [], from: nil, step: 1) == nil)
    }
}
