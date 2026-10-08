import SwiftUI
import IterCore
import IterDesign
import IterFeatures

/// iPhone Explore tab, the root of the Explore stack in the shell's sheet (the map is behind the sheet, `PhoneShell`).
/// As in Find My: the title and buttons are the navigation bar's, and an opened place is pushed. OWNER: Explore.
struct PhoneExploreScreen: View {
    @Environment(ExploreModel.self) private var explore

    var body: some View {
        if AppLaunch.previewSearch {
            ExploreSearchScreen()
        } else {
            ExploreBrowser(explore: explore, usesNavigationBar: true)
                .navigationTitle(String(localized: "Explore", comment: "Explore sheet title"))
                .navigationSubtitle(subtitle)
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        ExploreMoreMenu(explore: explore)
                        ExploreShareLink(explore: explore)
                    }
                }
                .navigationDestination(isPresented: placeShown) {
                    if let row = explore.selectedRow {
                        ExplorePlaceDetail(explore: explore, row: row, usesNavigationBar: true)
                    }
                }
        }
    }

    private var placeShown: Binding<Bool> {
        Binding(get: { explore.showsPanel }, set: { if !$0 { explore.closePanel() } })
    }

    private var subtitle: String {
        let n = explore.rows.count
        if explore.isLoadingForecasts { return String(localized: "Loading forecasts…", comment: "Explore sheet subtitle") }
        return n == 1 ? String(localized: "1 place", comment: "Explore sheet subtitle") : String(localized: "\(n) places", comment: "Explore sheet subtitle: number of places listed")
    }
}
