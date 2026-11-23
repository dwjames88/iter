import SwiftUI
import Testing
import IterFeatures
import IterModel
import IterUI
@testable import IterScreens

/// Renders every Conditions state offscreen, light and dark, into Design/snapshots/rebuild/screens/. Glass does not draw
/// there; these screens are content-layer only, so the PNGs are faithful.
@MainActor @Suite(.serialized) struct ConditionsSnapshotTests {
    static let sections = CGSize(width: 600, height: 3500)

    private func sections(_ name: String, _ state: ConditionsPreviewState, configure: (inout ConditionsFixtures.Options) -> Void = { _ in }) async throws {
        let model = ConditionsPreviewData.model(state, configure: configure)
        let urls = try await Snapshot.record(ConditionsSections(model: model), name: name, size: Self.sections, background: IterColor.backgroundWindow)
        #expect(urls.count == 2)
    }

    @Test func loading() async throws { try await sections("conditions-loading", .loading) }
    @Test func quick() async throws { try await sections("conditions-quick", .quick) }
    @Test func complete() async throws { try await sections("conditions-complete", .complete) }
    @Test func stale() async throws { try await sections("conditions-stale", .stale) }
    @Test func offline() async throws { try await sections("conditions-offline", .offline) }
    @Test func outOfCoverage() async throws { try await sections("conditions-out-of-coverage", .outOfCoverage) }

    @Test func completeWithComparisonAlertMilitary() async throws {
        try await sections("conditions-complete-comparison-alert-military", .complete) {
            $0.withComparison = true; $0.withAlert = true; $0.militaryStation = true
        }
    }

    @Test func summaries() async throws {
        for (name, state) in [("conditions-summary-quick", ConditionsPreviewState.quick), ("conditions-summary-complete", .complete)] {
            let model = ConditionsPreviewData.model(state)
            try await Snapshot.record(ConditionsSummary(model: model).padding(16), name: name, size: CGSize(width: 400, height: 160),
                                      background: IterColor.backgroundWindow)
        }
    }

    @Test func compassAtTwoTimes() async throws {
        let model = ConditionsPreviewData.model(.complete)
        let day = model.selectedDay.start(in: model.place.timeZone)
        for (name, hour) in [("conditions-compass-0645", 6.75), ("conditions-compass-1830", 18.5)] {
            model.scrubTime = day.addingTimeInterval(hour * 3600)
            try await Snapshot.record(SkyModule(model: model).padding(16), name: name, size: CGSize(width: 600, height: 640),
                                      background: IterColor.backgroundWindow)
        }
    }

    @Test func compassFollowsScrubTime() async throws {
        let model = ConditionsPreviewData.model(.complete)
        let day = model.selectedDay.start(in: model.place.timeZone)
        model.scrubTime = day.addingTimeInterval(7 * 3600)
        let morning = model.compass
        model.scrubTime = day.addingTimeInterval(18 * 3600)
        #expect(model.compass != morning)
        #expect(morning.sun.azimuth < 180 && model.compass.sun.azimuth > 180)
    }

    @Test func placePage() async throws {
        let container = try AppContainer.test(seed: true)
        let library = container.libraryModel()
        let model = ConditionsPreviewData.model(.complete) { $0.withComparison = true }
        let spots = try await FindPreviewData.model(.empty).spots
        let page = PlacePageScreen(place: ConditionsFixtures.place, conditions: model, library: library,
                                   readout: { spots.readout(for: $0.coordinate, elevationMeters: $0.elevationMeters) })
            .environment(AppNavigator())
        try await Snapshot.record(page, name: "place-page", size: CGSize(width: 700, height: 3500), background: IterColor.backgroundWindow)
    }
}
