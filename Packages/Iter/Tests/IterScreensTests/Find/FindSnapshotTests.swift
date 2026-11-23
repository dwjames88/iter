import SwiftUI
import Testing
import IterFeatures
import IterModel
import IterUI
@testable import IterScreens

/// The Find card's states rendered without the map (MapKit and system glass do not draw offscreen), light and dark, into
/// Design/snapshots/rebuild/screens/. The card sits on a flat window colour standing in for the glass.
@MainActor @Suite struct FindSnapshotTests {
    static let cardSize = CGSize(width: 400, height: 900)

    private func card<Content: View>(_ content: Content) -> some View {
        content
            .environment(\.isOnGlass, true)
            .environment(AppNavigator())
            .background(IterColor.backgroundWindow)
    }

    private func record(_ model: FindModel, name: String, size: CGSize = cardSize, conditions: ConditionsModel? = nil,
                        showsSearchHere: Bool = false, sources: Bool = false) async throws {
        let view = card(FindCardContent(model: model, conditions: conditions, showsSearchHere: showsSearchHere, initiallyShowsSources: sources))
        _ = try await Snapshot.record(view, name: name, size: size)
    }

    @Test func empty() async throws {
        // Nothing searched: no card, only the hint over the (here blank) map.
        let model = try await FindPreviewData.model(.empty)
        #expect(FindCardMode.of(model) == .hidden)
        let view = FindEmptyHint().frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.gray.opacity(0.35))
        _ = try await Snapshot.record(view, name: "find-empty", size: CGSize(width: 720, height: 460))
    }

    @Test func searching() async throws {
        let model = try await FindPreviewData.model(.searching)
        #expect(FindCardMode.of(model) == .results)
        try await record(model, name: "find-searching")
    }

    @Test func results() async throws {
        let model = try await FindPreviewData.model(.results)
        try await record(model, name: "find-results", showsSearchHere: true)
    }

    @Test func basicSearch() async throws {
        let model = try await FindPreviewData.model(.basicSearch)
        #expect(model.planLabel?.hasPrefix("Basic search") == true)
        try await record(model, name: "find-basic-search")
    }

    @Test func sourceDown() async throws {
        let model = try await FindPreviewData.model(.sourceDown)
        try await record(model, name: "find-source-down", sources: true)
    }

    @Test func sourcesList() async throws {
        let model = try await FindPreviewData.model(.searching)
        try await record(model, name: "find-sources-list", sources: true)
    }

    @Test func suggestions() async throws {
        let model = try await FindPreviewData.model(.empty)
        model.text = "waterfalls near Lone Pine at sunrise"
        #expect(FindCardMode.of(model) == .suggestions)
        #expect(model.suggestions.ask != nil)
        try await record(model, name: "find-suggestions", size: CGSize(width: 400, height: 500))
    }

    @Test func lookup() async throws {
        let model = try await FindPreviewData.model(.empty)
        model.text = "Mesa Arch"
        model.submit()
        for _ in 0..<200 where model.phase != .finished { try await Task.sleep(for: .milliseconds(10)) }
        #expect(FindCardMode.of(model) == .lookup)
        try await record(model, name: "find-lookup", size: CGSize(width: 400, height: 500))
    }

    @Test func placeCard() async throws {
        let model = try await FindPreviewData.model(.results)
        let id = try #require(model.rows.first?.id)
        model.select(id)
        let conditions = ConditionsPreviewData.model(.quick)
        try await record(model, name: "find-place-card", size: CGSize(width: 400, height: 1100), conditions: conditions)
    }

    @Test func placeCardOwnSpot() async throws {
        let model = try await FindPreviewData.model(.empty)
        let dropped = await model.dropPin(at: Coordinate(latitude: 38.4012, longitude: -109.8541))
        #expect(dropped != nil)
        #expect(model.card?.isOwn == true)
        try await record(model, name: "find-place-card-own-spot", size: CGSize(width: 400, height: 1200))
    }
}
