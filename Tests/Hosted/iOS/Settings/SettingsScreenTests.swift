import SwiftUI
import Testing
import IterFeatures
@testable import Iter

@MainActor
@Suite struct SettingsScreenTests {
    private func shell(seed: Bool = false) throws -> IOSShell {
        IOSShell(container: try AppContainer.test(seed: seed))
    }

    @Test func aboutReadsTheBundle() {
        #expect(IOSAbout.versionText != "")
        #expect(IOSAbout.versionText(Bundle(for: SettingsHostMarker.self)) != "")
    }

    @Test func sourceWordsMatchTheMac() {
        #expect(IOSSourceText.status(.offByDefault) == "Off Until You Turn It On")
        #expect(IOSSourceText.status(.unavailable("no api")) == "Unavailable: No api")
        #expect(IOSSourceText.timing(.nextLaunch) == "Applies the next time Iter opens.")
        #expect(IOSSourceText.timing(.never) == nil)
    }

    #if DEBUG
    @Test func debugReasonNamesTheRealLibrary() {
        #expect(IOSDebugText.reason(DebugActionError.refusedOnRealStore).contains("real library"))
        #expect(IOSDebugText.sampleKey == "IterDebugSampleData")
    }

    @Test func seedAndResetWorkOnAScratchStore() throws {
        let s = try shell()
        _ = try s.container.seedSampleTrip()
        s.library.refresh()
        #expect(!s.library.trips.isEmpty)
        try s.container.resetLibrary()
        s.library.refresh()
        #expect(s.library.trips.isEmpty)
    }
    #endif

    @Test(arguments: SettingsHarnessAppearance.allCases) func rendersTheRootAndTheSourcesPane(_ appearance: SettingsHarnessAppearance) async throws {
        let s = try shell()
        let size = CGSize(width: 402, height: 874)
        let root = NavigationStack { SettingsRoot(model: s.settings, shell: s) }
        let rootImage = try await SettingsHarness.render(root, name: "settings-root", size: size, appearances: [appearance])
        #expect(!SettingsHarness.isBlank(try #require(rootImage.first)))
        let sources = NavigationStack { IOSSourcesSettings(model: s.settings) }
        let image = try await SettingsHarness.render(sources, name: "settings-sources", size: size, appearances: [appearance])
        #expect(!SettingsHarness.isBlank(try #require(image.first)))
        let search = NavigationStack { IOSSearchSettings(model: s.settings) }
        _ = try await SettingsHarness.render(search, name: "settings-search", size: size, appearances: [appearance])
    }
}

final class SettingsHostMarker {}
