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
                .padding(.top, IterSpace.lg)
                .frame(width: Self.columnWidth)
                .frame(maxHeight: .infinity)
                .background(IterColor.backgroundContent.opacity(0.88), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(IterColor.separator, lineWidth: 0.5))
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .shadow(color: .black.opacity(0.2), radius: 18, y: 4)
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
