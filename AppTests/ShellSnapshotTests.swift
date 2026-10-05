import SwiftUI
import Testing
@testable import Iter

@MainActor
@Suite(.serialized) struct ShellSnapshotTests {
    @Test(.enabled(if: Snapshot.enabled)) func shell() async throws {
        let model = Fixtures.model()
        try await Snapshot.render(Fixtures.host(RootView(), model: model), screen: "shell", state: "default")
    }

    @Test func modelBuilds() {
        let model = Fixtures.model()
        #expect(model.store.trips().count == 1)
    }
}
