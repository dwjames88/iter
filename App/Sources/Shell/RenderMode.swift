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
            // Snapshots draw them as the flat system window colour instead (sidebar and Settings only; the app's own
            // lists use `paperListBackground`).
            content.scrollContentBackground(.hidden).background(IterColor.backgroundSystemWindow)
        } else {
            content
        }
    }
}

/// The app's own list panels (Saved, Scout, Explore list) sit on First Light paper in live and snapshot renders.
private struct PaperListBackground: ViewModifier {
    func body(content: Content) -> some View {
        content.scrollContentBackground(.hidden).background(IterColor.backgroundContent)
    }
}

extension View {
    func paperListBackground() -> some View { modifier(PaperListBackground()) }
    func snapshotOpaqueBackground() -> some View { modifier(SnapshotOpaqueBackground()) }
}
