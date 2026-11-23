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
        let conditions = ConditionsPreviewData.model(.complete)
        #expect(model.cardScore?.value != nil)
        try await record(model, name: "find-place-card", size: CGSize(width: 400, height: 1100), conditions: conditions)
    }

    @Test func placeCardOwnSpot() async throws {
        let model = try await FindPreviewData.model(.empty)
        let dropped = await model.dropPin(at: Coordinate(latitude: 38.4012, longitude: -109.8541))
        #expect(dropped != nil)
        #expect(model.card?.isOwn == true)
        try await record(model, name: "find-place-card-own-spot", size: CGSize(width: 400, height: 1200))
    }

    /// The map pins: rank plates, the score chip on the selected and top results, an unscored pin keeping its rank.
    @Test func pins() async throws {
        let model = try await FindPreviewData.model(.results)
        let pins = model.mapContent.pins.filter { if case .result = $0.kind { true } else { false } }
        #expect(pins.contains { $0.score?.value != nil })
        var unscored = try #require(pins.last)
        unscored.score = nil
        let selected = pins[1]
        let row = HStack(alignment: .bottom, spacing: 16) {
            ForEach(Array(pins.prefix(3).enumerated()), id: \.offset) { _, pin in FindPinView(pin: pin) }
            FindPinView(pin: selected, isSelected: true)
            FindPinView(pin: unscored)
        }
        .padding(24)
        _ = try await Snapshot.record(row, name: "find-pins", size: CGSize(width: 420, height: 110), background: IterColor.backgroundWindow)
    }

    @Test func aPinShowsItsChipOnlyForAKnownScoreNearTheTopOrSelected() async throws {
        let model = try await FindPreviewData.model(.results)
        var pin = try #require(model.mapContent.pins.first { if case .result = $0.kind { true } else { false } })
        #expect(pin.showsChip(isSelected: false))
        pin.score = nil
        #expect(!pin.showsChip(isSelected: true))
        pin.score = FindScore(kind: .goldenEvening, start: .now, value: 60, confidence: .high, isLoading: false, zoneIdentifier: "America/Denver")
        pin.kind = .result(rank: 9)
        #expect(!pin.showsChip(isSelected: false) && pin.showsChip(isSelected: true))
    }

    @Test func theWhyLineIsLabelledOnlyWhenTheModelWroteIt() async throws {
        let model = try await FindPreviewData.model(.results)
        let written = try #require(model.rows.first { $0.whyIsModelWritten })
        #expect(written.why != nil)
        #expect(model.rows.contains { !$0.whyIsModelWritten })
    }
}
