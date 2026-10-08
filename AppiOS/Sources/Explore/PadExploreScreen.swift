import SwiftUI
import IterCore
import IterDesign
import IterFeatures

/// iPad Find: map with a floating panel column (list, then the light panel). OWNER: Explore.
struct PadExploreScreen: View {
    @Environment(ExploreModel.self) private var explore

    private static let columnWidth: CGFloat = 380

    var body: some View {
        @Bindable var explore = explore
        ZStack(alignment: .topLeading) {
            ExploreMapLayer(explore: explore, leadingInset: Self.columnWidth + IterSpace.lg)
            ExploreBrowser(explore: explore)
                .environment(\.isOnGlass, true)
                .padding(.top, IterSpace.lg)
                .frame(width: Self.columnWidth)
                .frame(maxHeight: .infinity)
                .clipShape(.rect(cornerRadius: 28))
                .glassEffect(.regular, in: .rect(cornerRadius: 28))
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
