import SwiftUI
import IterCore
import IterDesign
import IterFeatures

/// iPhone Explore tab: the list and place panel in the shell's sheet. The map is behind the sheet (`PhoneShell`), as in
/// Find My. OWNER: Explore.
struct PhoneExploreScreen: View {
    @Environment(ExploreModel.self) private var explore

    var body: some View {
        if AppLaunch.previewSearch {
            ExploreSearchScreen()
        } else {
            ExploreBrowser(explore: explore)
                .padding(.top, IterSpace.lg)
                .toolbar(.hidden, for: .navigationBar)
        }
    }
}
