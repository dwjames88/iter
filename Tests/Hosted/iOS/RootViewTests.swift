import Foundation
import Testing
import IterFeatures
@testable import Iter

@Suite struct RootViewTests {
    @Test func phoneTabsAreTheFourStages() {
        #expect(PhoneTab.allCases == [.find, .trips, .saved, .go])
    }

    /// The owner's phone keeps its library under com.dwjames.iter.ios: on iOS that id (and only outside a test host) is the real
    /// app, so it opens the real store; before Phase 7 the Mac id was the only real one and the phone would have opened memory.
    @Test func theIPhoneBundleIDIsTheRealApp() {
        #expect(StorePlacement.realBundleID == "com.dwjames.iter.ios")
        #expect(StorePlacement.isRealProcess(bundleID: "com.dwjames.iter.ios", environment: [:]))
        #expect(!StorePlacement.isRealProcess(bundleID: "com.dwjames.iter", environment: [:]))
        #expect(!StorePlacement.isRealProcess(bundleID: "com.dwjames.iter.ios", environment: ["XCTestConfigurationFilePath": "x"]))
    }
}
