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
        // `ignoresSafeAreaEdges: []` keeps the paper below the toolbar: a plain `.background` extends under the
        // transparent macOS 26 toolbar, which painted an opaque block over the list column only.
        content.scrollContentBackground(.hidden).background(IterColor.backgroundContent, ignoresSafeAreaEdges: [])
    }
}

extension View {
    func paperListBackground() -> some View { modifier(PaperListBackground()) }
    /// One toolbar bar across the whole window. On macOS 26 the toolbar is transparent and shows whatever is behind
    /// it, so a paper column and a map next to each other drew two different bars with a seam. Asking for the system
    /// toolbar background draws one continuous bar; panels must not extend their own backgrounds under it.
    func unifiedToolbarBackground() -> some View {
        #if os(macOS)
        toolbarBackgroundVisibility(.visible, for: .windowToolbar)
        #else
        self
        #endif
    }
    func snapshotOpaqueBackground() -> some View { modifier(SnapshotOpaqueBackground()) }
}
