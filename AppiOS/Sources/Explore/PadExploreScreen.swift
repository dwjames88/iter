import SwiftUI
import IterCore
import IterDesign
import IterFeatures

/// iPad Find: map with a floating panel column (list, then the light panel). OWNER: Explore.
struct PadExploreScreen: View {
    @Environment(ExploreModel.self) private var explore

    private static let columnWidth: CGFloat = 380
    /// Concentric with the window's corners, as the system's own floating panels are.
    private static let shape = ConcentricRectangle(corners: .concentric(minimum: 16), isUniform: true)

    var body: some View {
        @Bindable var explore = explore
        ZStack(alignment: .topLeading) {
            ExploreMapLayer(explore: explore, leadingInset: Self.columnWidth + IterSpace.lg)
            ExploreBrowser(explore: explore)
                .environment(\.isOnGlass, true)
                .padding(.top, IterSpace.lg)
                .frame(width: Self.columnWidth)
                .frame(maxHeight: .infinity)
                .clipShape(Self.shape)
                .glassEffect(.regular, in: Self.shape)
                .padding(IterSpace.lg)
        }
        .navigationTitle(String(localized: "Find", comment: "iPad Find screen title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        .searchable(text: $explore.query, placement: .navigationBarDrawer(displayMode: .automatic),
                    prompt: Text("Search places or ask Iter", comment: "Explore search field prompt"))
        .onSubmit(of: .search) { explore.submitSearch() }
        .onAppear { explore.requestInitialCamera() }
    }
}
