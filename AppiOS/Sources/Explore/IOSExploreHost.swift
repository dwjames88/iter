import SwiftUI
import IterFeatures

/// Owns the one ExploreModel for the scene (Explore tab, Search tab and the iPad Find screen share it), applies the Explore
/// launch switches once, and puts it in the environment.
struct IOSExploreHost<Content: View>: View {
    @Environment(AppModel.self) private var model
    @State private var explore: ExploreModel?
    @ViewBuilder var content: () -> Content

    var body: some View {
        if let explore {
            content().environment(explore)
        } else {
            Color.clear.onAppear { explore = ExploreModel(app: model) }
        }
    }
}
