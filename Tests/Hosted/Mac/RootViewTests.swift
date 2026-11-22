import Testing
@testable import Iter

@Suite struct RootViewTests {
    @Test func rootViewTypeExists() {
        #expect(String(describing: RebuildRootView.self) == "RebuildRootView")
    }
}
