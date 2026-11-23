import IterGoActivity
import SwiftUI
import Testing
@testable import Iter

/// Renders the Live Activity, Dynamic Island and widget views for every sample state, light and dark, and checks the
/// words each one says. PNGs are written to Design/snapshots/rebuild/go only when ITER_SNAPSHOT_RECORD=1.
@MainActor
@Suite struct GoWidgetRenderTests {
    @Test(arguments: GoRenderCase.all.map(\.name))
    func activityAndIsland(name: String) async throws {
        let c = try #require(GoRenderCase.all.first { $0.name == name })
        let images = try await GoHarness.render(GoActivitySheet(c: c), name: "go-activity-\(name)", size: GoActivitySheet.size)
        #expect(images.count == 2)
        for image in images { #expect(!GoHarness.isBlank(image)) }
    }

    @Test(arguments: GoRenderCase.all.map(\.name))
    func widgets(name: String) async throws {
        let c = try #require(GoRenderCase.all.first { $0.name == name })
        let images = try await GoHarness.render(GoWidgetSheet(c: c), name: "go-widgets-\(name)", size: GoWidgetSheet.size)
        #expect(images.count == 2)
        for image in images { #expect(!GoHarness.isBlank(image)) }
    }
}
