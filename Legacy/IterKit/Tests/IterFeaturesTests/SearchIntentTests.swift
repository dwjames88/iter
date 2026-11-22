import Testing
@testable import IterFeatures

@Suite struct SearchIntentTests {
    @Test(arguments: ["Portland", "Mesa Arch", "Yosemite Valley", "Cannon Beach Oregon", "Moab", "Horseshoe Bend",
                      "Mount Rainier National Park", "Valley of the Gods", "San Francisco, CA", "Zürich",
                      "Great Smoky Mountains National Park", "Nearby Lake", "Fortress Rock", "Withrow", "Spotsylvania",
                      "Grand Teton National Park Wyoming"])
    func placeNamesStayPlaces(_ query: String) {
        #expect(SearchIntent.classify(query) == .place)
    }

    @Test(arguments: ["foggy forest within two hours of Portland for sunrise", "where can I shoot sunset?",
                      "find waterfalls near me", "quiet beach for blue hour", "Waterfalls near Seattle that work on overcast days"])
    func requestsAreAsks(_ query: String) {
        #expect(SearchIntent.classify(query) == .ask)
    }

    @Test func wordCountAloneNeverAsks() {
        #expect(SearchIntent.classify("one two three four five") == .place)
        #expect(SearchIntent.classify("  Great   Smoky Mountains\tNational\nPark ") == .place)
        #expect(SearchIntent.classify("a b c d e f g h i j") == .place)
    }

    @Test(arguments: ["Hoh Rain Forest", "Pacific Coast", "Misty Fjords", "Golden Hour Point", "Blue Hour Bay", "Milky Way Lake",
                      "Sunrise Point", "Sunset Cliffs", "Foggy Bottom", "Fog Lake", "Near Island", "Lakes with views", "Parks for kids",
                      "Within Reach", "Hours Creek", "Drive Thru Tree"])
    func keywordsAnywhereAsk(_ query: String) {
        #expect(SearchIntent.classify(query) == .ask)
    }

    @Test(arguments: ["Find", "Show waterfalls", "take a drive", "Help", "give ideas", "Suggest", "Plan a trip", "Shoot Moab",
                      "Photograph arches", "See Moab", "Watch the sunrise", "Catch the light", "Explore Utah", "Visit Zion",
                      "Hike Angels Landing", "Go west", "Get lost", "Want arches", "Need fog", "Chase storms"])
    func verbOpenersAsk(_ query: String) {
        #expect(SearchIntent.classify(query) == .ask)
    }

    @Test func verbsOnlyCountAsTheFirstWord() {
        #expect(SearchIntent.classify("Moab Go Karts") == .place)
        #expect(SearchIntent.classify("Seeley Lake") == .place)
        #expect(SearchIntent.classify("Gettysburg") == .place)
        #expect(SearchIntent.classify("Planet Hollywood") == .place)
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
        #expect(SearchIntent.classify("Nearby Lake") == .place)
        #expect(SearchIntent.classify("Fortress Rock") == .place)
        #expect(SearchIntent.classify("Withrow Moraine") == .place)
        #expect(SearchIntent.classify("Forestville") == .place)
        #expect(SearchIntent.classify("Coastal Trail") == .place)
        #expect(SearchIntent.classify("Driveway Rock") == .place)
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
