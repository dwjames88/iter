import SwiftUI
import IterFeatures

/// The Trip Builder panel (header card, day selector, day cards, transfers, source line). No background of its own: on the Mac it
/// sits in the system inspector, on iPhone in a pushed screen. Reads `AppNavigator` from the environment (and, optionally,
/// `LibraryModel` for Duplicate and Delete Trip). Calls `model.open()` when it appears and `model.close()` when it goes.
public struct TripBuilderPanel: View {
    let model: BuildModel
    public init(model: BuildModel) { self.model = model }
    public var body: some View { TripBuilderPanelContent(model: model) }
}
