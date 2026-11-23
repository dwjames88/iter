import Testing
@testable import Iter

@Suite struct RootViewTests {
    @Test func phoneTabsAreTheFourStages() {
        #expect(PhoneTab.allCases == [.find, .trips, .saved, .go])
    }
}
