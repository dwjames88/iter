import SwiftUI
import Testing
import IterUpdater
@testable import Iter

@MainActor
@Suite(.serialized) struct UpdateSnapshotTests {
    private func controller(_ phase: UpdateController.Phase, blockers: Bool = false) -> UpdateController {
        let c = UpdateController(updater: nil, defaults: UserDefaults(suiteName: "iter.updates.snap.\(UUID().uuidString)")!, presentsWindow: false)
        c.phase = phase
        return c
    }

    private var item: UpdateItem {
        UpdateControllerTests.item("0.2.0", build: 412).with(notes: "## Added\n- **Updates**: Iter can now update itself.\n- A new Settings ▸ Updates tab.\n\n## Fixed\n- Trips with no stops open again.")
    }

    @Test(.enabled(if: Snapshot.enabled)) func updateWindow() async throws {
        let size = Snapshot.Size(name: "560x560", width: 560, height: 560)
        let short = Snapshot.Size(name: "560x260", width: 560, height: 260)
        try await Snapshot.render(UpdateWindowView(controller: controller(.available(item))), screen: "update", state: "available", sizes: [size], chrome: .bare)
        let downloading = controller(.downloading(fraction: 0.4))
        try await Snapshot.render(UpdateWindowView(controller: downloading), screen: "update", state: "downloading", sizes: [short], chrome: .bare)
        try await Snapshot.render(UpdateWindowView(controller: controller(.upToDate)), screen: "update", state: "up-to-date", sizes: [short], chrome: .bare)
        let failed = controller(.failed(message: UpdateText.message(for: UpdateError.hashMismatch), item: nil))
        try await Snapshot.render(UpdateWindowView(controller: failed), screen: "update", state: "failed", sizes: [short], chrome: .bare)
    }

    @Test(.enabled(if: Snapshot.enabled)) func updatesPane() async throws {
        let size = Snapshot.Size(name: "640x480", width: 640, height: 480)
        try await Snapshot.render(UpdatesSettingsPane(controller: controller(.idle)), screen: "settings-updates", state: "default", sizes: [size], chrome: .bare)
    }
}

private extension UpdateItem {
    func with(notes: String) -> UpdateItem { var copy = self; copy.notes = notes; return copy }
}
