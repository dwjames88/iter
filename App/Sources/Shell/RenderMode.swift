import SwiftUI
import IterDesign

/// Live maps do not render offscreen. Snapshot renders set `.snapshot` and map views draw a static stand-in instead.
enum RenderMode: Sendable { case live, snapshot }

extension EnvironmentValues {
    @Entry var renderMode: RenderMode = .live
}

private struct SnapshotOpaqueBackground: ViewModifier {
    @Environment(\.renderMode) private var renderMode
    func body(content: Content) -> some View {
        if renderMode == .snapshot {
            // Translucent materials need the window server's backdrop, which an offscreen render does not have.
            // Snapshots draw them as the flat window colour instead.
            content.scrollContentBackground(.hidden).background(IterColor.backgroundWindow)
        } else {
            content
        }
    }
}

extension View {
    func snapshotOpaqueBackground() -> some View { modifier(SnapshotOpaqueBackground()) }
}
