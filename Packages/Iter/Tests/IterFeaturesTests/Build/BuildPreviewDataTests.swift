import Foundation
import Testing
import IterModel
@testable import IterFeatures

@MainActor
@Suite struct BuildPreviewDataTests {
    @Test func readyHasEveryDriveAndScore() {
        let model = BuildPreviewData.canyonCountry(.ready)
        #expect(model.header?.name == "Canyon Country" && model.header?.stopCount == 6 && model.header?.dayCount == 4)
        #expect(model.driveRows.count == 5)
        #expect(model.driveRows.allSatisfy { $0.state == .ready && !$0.isEstimate })
        #expect(model.driveRows.allSatisfy { if case .trafficAware = $0.basis { true } else { false } })
        #expect(model.stops.allSatisfy { $0.score != nil && !$0.scoreIsImproving })
        #expect(model.stops.map(\.score) == [82, 64, 91, 58, 76, 47])
        #expect(model.conditionsProgress.text == "Conditions: all 6 stops ready")
        #expect(model.header?.issueCount == 0)
        #expect(model.dayItems.map(\.bestScore) == [82, 91, 76, 47])
        #expect(!model.isLoadingDrives && model.directionsRequestCount == 0, "previews never ask for anything")
    }

    @Test func selectionsAreApplied() {
        let model = BuildPreviewData.canyonCountry(.ready, selectedDay: 1, selectedStop: 3)
        #expect(model.selectedDay == 1)
        #expect(model.selectedStopID == model.stops[2].id)
    }

    @Test func loadingDrivesShowEstimatesAndFailedOnesShowTheRetry() {
        let loading = BuildPreviewData.canyonCountry(.loadingDrives)
        #expect(loading.driveRows.allSatisfy { $0.state == .loading && $0.isEstimate })
        let failed = BuildPreviewData.canyonCountry(.driveFailed)
        #expect(failed.driveRows.allSatisfy { if case .failed = $0.state { true } else { false } })
        #expect(failed.driveRows.allSatisfy { $0.isEstimate })
    }

    @Test func aDriveThatCannotFitIsAConflict() {
        let model = BuildPreviewData.canyonCountry(.driveDoesNotFit)
        #expect(model.driveRows.contains { !$0.fits })
        #expect((model.header?.issueCount ?? 0) > 0)
    }

    @Test func scoresLoadingKeepsTheQuickOnesAndNamesTheSlowSource() {
        let model = BuildPreviewData.canyonCountry(.scoresLoading)
        #expect(model.stops.filter { $0.score != nil }.count == 3)
        #expect(model.stops.filter(\.scoreIsImproving).count == 3)
        #expect(model.conditionsProgress.text == "Conditions: 0 of 6 stops ready; NOAA forecast still loading for 3; waiting for a first score for 3")
    }

    @Test func aBackwardsDayHasTheSuggestion() {
        let model = BuildPreviewData.canyonCountry(.backwardsDay)
        #expect(model.suggestion(forDay: 2) != nil)
        #expect(model.rows.contains { if case .suggestion = $0.kind { true } else { false } })
    }

    @Test func anEmptyTripHasDaysAndNoStops() {
        let model = BuildPreviewData.canyonCountry(.empty)
        #expect(model.header?.dayCount == 3 && model.header?.stopCount == 0)
        #expect(model.stops.isEmpty && model.mapContent.waypoints.isEmpty && model.cameraRegion == nil)
        #expect(model.dayItems.map(\.stopCount) == [0, 0, 0])
    }

    @Test func aStartPlaceGivesTheFirstDayALeaveBy() {
        let model = BuildPreviewData.canyonCountry(.ready, startPlace: true)
        #expect(model.startPlace?.name == "Salt Lake City")
        #expect(model.startPlace?.firstLeaveBy != nil)
        #expect(model.transferRows.first?.day == 0)
    }
}
