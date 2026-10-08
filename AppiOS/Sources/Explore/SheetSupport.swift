import SwiftUI
import IterFeatures
import IterDesign

/// The three resting heights of the phone's sheet, for the `-IterSheet peek|half|full` launch switch.
enum SheetDetent: String, CaseIterable, Sendable {
    case peek, half, full
}

extension EnvironmentValues {
    /// True inside the phone's floating sheet (`PhoneShell`), whose Liquid Glass is the screens' ground, as in Find My.
    @Entry var isInFloatingSheet = false
}

extension View {
    /// A screen's paper ground, except inside the phone's floating sheet, where the sheet's own glass shows instead.
    func screenBackground(ignoresSafeAreaEdges edges: Edge.Set = .all) -> some View {
        modifier(ScreenBackground(edges: edges))
    }
}

private struct ScreenBackground: ViewModifier {
    let edges: Edge.Set
    @Environment(\.isInFloatingSheet) private var isInFloatingSheet

    func body(content: Content) -> some View {
        content.background(isInFloatingSheet ? Color.clear : IterColor.backgroundWindow, ignoresSafeAreaEdges: edges)
    }
}

/// What the map behind the phone's sheet shows for tabs other than Explore, as Find My's map follows its tabs. Screens
/// in the sheet publish their content here.
@MainActor
@Observable
final class PhoneBackdrop {
    /// The Locations tab's spots, as listed (search and filter applied).
    var locations: [SavedItem] = []
}
