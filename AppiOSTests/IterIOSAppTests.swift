import Testing
@testable import Iter

@Suite struct IterIOSLaunchTests {
    @Test func colorSchemeSwitchIsOffByDefault() {
        #expect(AppLaunch.forcedColorScheme == nil)
    }
}
