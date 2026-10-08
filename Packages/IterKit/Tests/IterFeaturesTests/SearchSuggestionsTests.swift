import Testing
import IterCore
@testable import IterFeatures

@Suite struct SearchSuggestionsTests {
    private func ids(_ list: [SearchSuggestion]) -> [String] { list.map(\.id) }

    @Test func emptyTextOffersNothing() {
        #expect(SearchSuggestions.make(query: "", askAvailability: .available).isEmpty)
        #expect(SearchSuggestions.make(query: "  \n ", askAvailability: .available).isEmpty)
    }

    @Test func aPlaceNameOffersOnlyAppleMaps() {
        for text in ["  Mesa Arch ", "Great Smoky Mountains National Park"] {
            let list = SearchSuggestions.make(query: text, askAvailability: .available)
            #expect(ids(list) == ["appleMaps"])
            #expect(list.map(\.isTop) == [true])
            #expect(list[0].kind == .appleMaps(query: text.trimmingCharacters(in: .whitespaces)))
        }
    }

    @Test func aRequestOffersAppleMapsFirstThenAsk() {
        let list = SearchSuggestions.make(query: "foggy forest within two hours of Portland", askAvailability: .available)
        #expect(ids(list) == ["appleMaps", "ask"])
        #expect(list.map(\.isTop) == [true, false])
        #expect(list.allSatisfy { $0.isAvailable })
        #expect(list[1].kind == .ask(query: "foggy forest within two hours of Portland", availability: .available))
    }

    @Test func anUnavailableAskStaysFlaggedAndNeverTops() {
        let list = SearchSuggestions.make(query: "foggy forest within two hours of Portland", askAvailability: .appleIntelligenceNotEnabled)
        #expect(ids(list) == ["appleMaps", "ask"])
        let ask = list[1]
        #expect(!ask.isAvailable)
        #expect(ask.unavailableReason == .appleIntelligenceNotEnabled)
        #expect(list[0].unavailableReason == nil)
        #expect(list[0].isTop && !ask.isTop)
    }

    @Test func anUnavailableAskIsNotOfferedForAPlaceName() {
        #expect(ids(SearchSuggestions.make(query: "Mesa Arch", askAvailability: .appleIntelligenceNotEnabled)) == ["appleMaps"])
    }
}
