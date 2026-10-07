import Testing
import IterCore
@testable import IterFeatures

@Suite struct SearchSuggestionsTests {
    private func ids(_ list: [SearchSuggestion]) -> [String] { list.map(\.id) }

    @Test func emptyTextOffersNothing() {
        #expect(SearchSuggestions.make(query: "", askAvailability: .available).isEmpty)
        #expect(SearchSuggestions.make(query: "  \n ", askAvailability: .available).isEmpty)
    }

    @Test func aPlaceNameRanksAppleMapsFirst() {
        let list = SearchSuggestions.make(query: "  Mesa Arch ", askAvailability: .available)
        #expect(ids(list) == ["appleMaps", "ask"])
        #expect(list.map(\.isTop) == [true, false])
        #expect(list[0].kind == .appleMaps(query: "Mesa Arch"))
        #expect(list[1].kind == .ask(query: "Mesa Arch", availability: .available))
    }

    @Test func aRequestRanksAskFirst() {
        let list = SearchSuggestions.make(query: "foggy forest within two hours of Portland", askAvailability: .available)
        #expect(ids(list) == ["ask", "appleMaps"])
        #expect(list.map(\.isTop) == [true, false])
        #expect(list.allSatisfy { $0.isAvailable })
    }

    @Test func anUnavailableAskStaysFlaggedAndNeverTops() {
        for text in ["Mesa Arch", "foggy forest within two hours of Portland"] {
            let list = SearchSuggestions.make(query: text, askAvailability: .appleIntelligenceNotEnabled)
            #expect(ids(list) == ["appleMaps", "ask"])
            let ask = list[1]
            #expect(!ask.isAvailable)
            #expect(ask.unavailableReason == .appleIntelligenceNotEnabled)
            #expect(list[0].unavailableReason == nil)
            #expect(list[0].isTop && !ask.isTop)
        }
    }
}
