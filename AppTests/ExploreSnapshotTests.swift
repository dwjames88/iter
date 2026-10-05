import SwiftUI
import Testing
import IterCore
import IterData
import IterFeatures
@testable import Iter

@MainActor
@Suite(.serialized) struct ExploreSnapshotTests {
    private func screen(_ model: AppModel, configure: (@MainActor (ExploreModel) -> Void)? = nil) -> some View {
        Fixtures.host(Fixtures.inDetailColumn(NavigationStack { ExploreView(configure: configure).spotDestination() }), model: model)
    }

    @Test(.enabled(if: Snapshot.enabled)) func defaultState() async throws {
        let model = Fixtures.model(weather: .sample)
        try await Snapshot.render(screen(model), screen: "explore", state: "default", settle: .seconds(2))
    }

    @Test(.enabled(if: Snapshot.enabled)) func selected() async throws {
        let model = Fixtures.model(weather: .sample)
        try await Snapshot.render(screen(model) { $0.select("mesa-arch", from: .list) }, screen: "explore", state: "selected", settle: .seconds(2))
    }

    @Test(.enabled(if: Snapshot.enabled)) func noForecast() async throws {
        let model = Fixtures.model(weather: .notEnabled)
        try await Snapshot.render(screen(model) { $0.select("mesa-arch", from: .list) }, screen: "explore", state: "noforecast", settle: .seconds(2))
    }

    @Test(.enabled(if: Snapshot.enabled)) func filteredEmpty() async throws {
        let model = Fixtures.model(weather: .sample)
        try await Snapshot.render(screen(model) { $0.filters.sources = [.yours] }, screen: "explore", state: "filtered-empty", settle: .seconds(1))
    }

    @Test(.enabled(if: Snapshot.enabled)) func addSpotMode() async throws {
        let model = Fixtures.model(weather: .sample)
        try await Snapshot.render(screen(model) { $0.beginAddingSpot() }, screen: "explore", state: "addspot-mode", settle: .seconds(2))
    }

    @Test func screenBuilds() {
        let model = Fixtures.model()
        let explore = ExploreModel(app: model)
        #expect(explore.rows.count == CuratedSpots.all.count)
    }
}
