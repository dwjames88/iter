import SwiftUI
import Testing
import IterCore
import IterData
import IterServices
import IterFeatures
@testable import Iter

/// Scout double for the Ask snapshots: reports a fixed availability and answers at once with fixed suggestions.
private struct SnapshotScout: Scouting {
    var state: ScoutAvailability = .available
    var suggestions: [ScoutSuggestion] = []
    func availability() -> ScoutAvailability { state }
    func scout(_ request: String, progress: @escaping @Sendable (ScoutProgress) -> Void) async throws -> [ScoutSuggestion] { suggestions }
}

@MainActor
@Suite(.serialized) struct ExploreAskSnapshotTests {
    private static let request = "Foggy forest spots within two hours of Portland for sunrise"

    private static func suggestions() -> [ScoutSuggestion] {
        let mesa = CuratedSpots.spot(id: "mesa-arch")!
        let tunnel = CuratedSpots.spot(id: "tunnel-view")!
        let maps1 = Spot(id: "maps-1", name: "Latourell Falls", locality: "Corbett, OR", coordinate: Coordinate(latitude: 45.5370, longitude: -122.2161),
                         timeZoneIdentifier: "America/Los_Angeles", category: .waterfall, origin: .appleMaps)
        let maps2 = Spot(id: "maps-2", name: "Hoyt Arboretum", locality: "Portland, OR", coordinate: Coordinate(latitude: 45.5100, longitude: -122.7160),
                         timeZoneIdentifier: "America/Los_Angeles", category: .forest, origin: .appleMaps)
        return [
            ScoutSuggestion(id: "maps-2", spot: maps2, provenance: .appleMaps,
                            why: "Tall conifers hold fog well into the morning, and the paths run east so the first sun comes through the trunks.",
                            suggestedWindow: .goldenMorning, driveSeconds: 12 * 60),
            ScoutSuggestion(id: "maps-1", spot: maps1, provenance: .appleMaps,
                            why: "A tall waterfall in a mossy gorge; overcast keeps the water even.", suggestedWindow: .goldenMorning, driveSeconds: 38 * 60),
            ScoutSuggestion(id: "tunnel-view", spot: tunnel, provenance: .curated,
                            why: "Valley fog fills below the viewpoint at first light.", suggestedWindow: .goldenMorning, driveSeconds: 95 * 60),
            ScoutSuggestion(id: "mesa-arch", spot: mesa, provenance: .curated, why: "", suggestedWindow: .goldenMorning, driveSeconds: nil),
        ]
    }

    private func screen(_ model: AppModel, configure: (@MainActor (ExploreModel) -> Void)? = nil) -> some View {
        Fixtures.host(Fixtures.inDetailColumn(NavigationStack { ExploreView(configure: configure).spotDestination() }), model: model)
    }

    /// The Ask section with its suggested places, each with the note under the row.
    @Test(.enabled(if: Snapshot.enabled)) func askResults() async throws {
        let model = Fixtures.model(weather: .sample, scout: SnapshotScout(suggestions: Self.suggestions()))
        try await Snapshot.render(screen(model) { explore in
            // Straight to the engine: a snapshot cannot draw the toolbar's search field, and text typed into it
            // makes AppKit's offscreen toolbar layout loop.
            explore.askModel.request = Self.request
            explore.askModel.run(area: nil)
        }, screen: "explore", state: "ask-results", settle: .seconds(2))
    }

    /// Apple Intelligence off: the honest message and "Search Apple Maps Instead".
    @Test(.enabled(if: Snapshot.enabled)) func askUnavailable() async throws {
        let model = Fixtures.model(weather: .sample, scout: SnapshotScout(state: .appleIntelligenceNotEnabled))
        try await Snapshot.render(screen(model) { explore in
            // Straight to the engine: a snapshot cannot draw the toolbar's search field, and text typed into it
            // makes AppKit's offscreen toolbar layout loop.
            explore.askModel.request = Self.request
            explore.askModel.run(area: nil)
        }, screen: "explore", state: "ask-unavailable", settle: .seconds(1))
    }
}
