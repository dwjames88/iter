import SwiftUI
import TipKit

/// The system tip on the place card of one of your own spots: how to move it. Shown inline with `TipView` until the user
/// drags a pin or uses Adjust Location (`invalidate(reason: .actionPerformed)`).
struct MoveSpotTip: Tip {
    /// One instance, so every card shows and invalidates the same tip.
    static let shared = MoveSpotTip()

    var title: Text { Text("Move This Spot", comment: "Tip title: how to move one of your own spots") }

    var message: Text? {
        #if os(macOS)
        Text("Drag the pin to move it, or choose Adjust Location.", comment: "Tip message on the Mac: moving your own spot")
        #else
        Text("Touch and hold the pin to move it, or choose Adjust Location.", comment: "Tip message on iPhone and iPad: moving your own spot")
        #endif
    }

    var image: Image? { Image(systemName: "mappin.and.ellipse") }

    var options: [any TipOption] { [Tips.IgnoresDisplayFrequency(true)] }

    /// Whether the card should offer the tip: only for a spot of yours, and never in a snapshot render unless it asks.
    static func isShown(canMove: Bool, renderMode: RenderMode, forced: Bool = false) -> Bool {
        guard canMove else { return false }
        return renderMode == .live || forced
    }

    /// Called once at launch by both apps. Never under the test runner (a unit or snapshot run keeps no tip state); a
    /// render copy (in-memory store) starts from a clean datastore so the tip is there for a screenshot.
    @MainActor static func configure() {
        guard !AppLaunch.isRunningTests else { return }
        if AppLaunch.inMemoryStore { try? Tips.resetDatastore() }
        try? Tips.configure()
    }

    /// The user moved a pin or used Adjust Location: they know how.
    static func didMove() { shared.invalidate(reason: .actionPerformed) }
}

extension EnvironmentValues {
    /// A snapshot that shows the tip sets this (snapshots hide it otherwise, so they stay deterministic).
    @Entry var showsMoveSpotTip = false
}

/// The tip, inline in the place card, for your own spots.
struct MoveSpotTipView: View {
    let canMove: Bool
    @Environment(\.renderMode) private var renderMode
    @Environment(\.showsMoveSpotTip) private var forced

    var body: some View {
        if MoveSpotTip.isShown(canMove: canMove, renderMode: renderMode, forced: forced) {
            TipView(MoveSpotTip.shared)
        }
    }
}
