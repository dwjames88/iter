import SwiftUI
import Testing
import IterFeatures
@testable import IterScreens

/// Renders the Trip Builder panel offscreen from the Canyon Country preview models. The models are not opened (nothing runs), and
/// the panel's own open/close is switched off, so every PNG is one fixed state. Glass and MapKit do not draw offscreen.
@MainActor @Suite(.serialized) struct BuilderPanelSnapshotTests {
    private func panel(_ model: BuildModel) -> some View {
        TripBuilderPanel(model: model)
            .environment(AppNavigator())
            .environment(\.tripBuilderOpensModel, false)
    }

    @Test func ready() async throws {
        let model = BuildPreviewData.canyonCountry(.ready, selectedDay: 1, selectedStop: 3)
        try await Snapshot.record(panel(model), name: "builder-panel", size: CGSize(width: 560, height: 1400))
    }

    @Test func allDays() async throws {
        let model = BuildPreviewData.canyonCountry(.ready)
        try await Snapshot.record(panel(model), name: "builder-panel-all-days", size: CGSize(width: 560, height: 2600))
    }

    @Test func loadingDrives() async throws {
        let model = BuildPreviewData.canyonCountry(.loadingDrives, selectedDay: 0)
        try await Snapshot.record(panel(model), name: "builder-panel-loading-drives", size: CGSize(width: 560, height: 1400))
    }

    @Test func driveFailed() async throws {
        let model = BuildPreviewData.canyonCountry(.driveFailed, selectedDay: 1)
        try await Snapshot.record(panel(model), name: "builder-panel-drive-failed", size: CGSize(width: 560, height: 1400))
    }

    @Test func conflictBackwards() async throws {
        let model = BuildPreviewData.canyonCountry(.backwardsDay, selectedDay: 2)
        try await Snapshot.record(panel(model), name: "builder-panel-conflict", size: CGSize(width: 560, height: 1400))
    }

    @Test func conflictDriveDoesNotFit() async throws {
        let model = BuildPreviewData.canyonCountry(.driveDoesNotFit, selectedDay: 1)
        try await Snapshot.record(panel(model), name: "builder-panel-conflict-drive", size: CGSize(width: 560, height: 1400))
    }

    @Test func scoresLoading() async throws {
        let model = BuildPreviewData.canyonCountry(.scoresLoading, selectedDay: 1)
        try await Snapshot.record(panel(model), name: "builder-panel-scores-loading", size: CGSize(width: 560, height: 1400))
    }

    @Test func startPlace() async throws {
        let model = BuildPreviewData.canyonCountry(.ready, selectedDay: 0, startPlace: true)
        try await Snapshot.record(panel(model), name: "builder-panel-start-place", size: CGSize(width: 560, height: 1400))
    }
}
