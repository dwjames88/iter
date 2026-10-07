import Testing
@testable import IterFeatures

@Suite struct SearchIntentTests {
    @Test(arguments: ["Portland", "Mesa Arch", "Yosemite Valley", "Cannon Beach Oregon", "Moab", "Horseshoe Bend",
                      "Mount Rainier National Park", "Valley of the Gods", "San Francisco, CA", "Zürich"])
    func placeNamesStayPlaces(_ query: String) {
        #expect(SearchIntent.classify(query) == .place)
    }

    @Test(arguments: ["foggy forest within two hours of Portland for sunrise", "where can I shoot sunset?",
                      "find waterfalls near me", "quiet beach for blue hour", "Waterfalls near Seattle that work on overcast days"])
    func requestsAreAsks(_ query: String) {
        #expect(SearchIntent.classify(query) == .ask)
    }

    @Test func fiveWordsIsAnAskFourIsNot() {
        #expect(SearchIntent.classify("one two three four") == .place)
        #expect(SearchIntent.classify("one two three four five") == .ask)
        #expect(SearchIntent.classify("  one   two three\tfour\nfive ") == .ask)
    }

    @Test func aQuestionMarkAlwaysAsks() {
        #expect(SearchIntent.classify("Moab?") == .ask)
    }

    @Test(arguments: ["Find Moab", "find", "Show me arches", "WHERE is the best light", "what", "Which canyon", "suggest a canyon",
                      "Recommend something", "looking for fog", "I want fog", "I\u{2019}d like fog", "I'd like fog", "Somewhere quiet",
                      "anywhere dark", "Take me west", "help me plan", "Give me ideas", "best places", "Best place east",
                      "good place", "Good places west", "Places", "spots near here", "Spots"])
    func requestOpenersAsk(_ query: String) {
        #expect(SearchIntent.classify(query) == .ask)
    }

    @Test(arguments: ["trails within 20 miles", "Bend 2 hours of Portland", "ten minutes of Moab", "5 miles of Page", "30 km of Oslo",
                      "a drive from Denver", "dark skies near me", "Arches for sunrise", "Zion for sunset", "Coast for golden hour",
                      "Beach for blue hour", "Desert for night", "Utah for the Milky Way"])
    func constraintMarkersAsk(_ query: String) {
        #expect(SearchIntent.classify(query) == .ask)
    }

    @Test func openersNeedAWordBoundary() {
        // Place names that merely begin with the letters of an opener are places.
        #expect(SearchIntent.classify("Finder Point") == .place)
        #expect(SearchIntent.classify("Whatcom Falls") == .place)
        #expect(SearchIntent.classify("Spotsylvania") == .place)
        #expect(SearchIntent.classify("Placerville") == .place)
        #expect(SearchIntent.classify("Whereby") == .place)
    }

    @Test func markersNeedAWordBoundary() {
        #expect(SearchIntent.classify("Nearly Me") == .place)
        #expect(SearchIntent.classify("Forsunrise") == .place)
    }

    @Test func caseDiacriticsAndPunctuationDoNotMatter() {
        #expect(SearchIntent.classify("FIND WATERFALLS") == .ask)
        #expect(SearchIntent.classify("Find, waterfalls.") == .ask)
        #expect(SearchIntent.classify("Café Près") == .place)
        #expect(SearchIntent.classify("réstaurants près d\u{2019}ici, for sunset") == .ask)
    }

    @Test func emptyAndBlankArePlaces() {
        #expect(SearchIntent.classify("") == .place)
        #expect(SearchIntent.classify("   ") == .place)
        #expect(SearchIntent.classify("...") == .place)
    }
}
