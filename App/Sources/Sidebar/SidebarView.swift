import SwiftUI
import IterCore
import IterData
import IterDesign
import IterFeatures

/// The sidebar: Find, Locations and Trips (each: its "All" page as a disclosure row, then what is pinned as its
/// children). A system source list built from `Components/Sidebar`; the sections are in their own files. The sidebar
/// toggle is the system one (NavigationSplitView's); nothing here hides or replaces it. Folders are managed inside All Trips and All Locations, not here.
struct SidebarView: View {
    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        @Bindable var navigation = navigation
        List(selection: $navigation.selection) {
            Section {
                SidebarRow(String(localized: "Explore", comment: "Sidebar item"), systemImage: "binoculars")
                    .tag(SidebarItem.explore)
            } header: {
                SidebarSectionHeader(String(localized: "Find", comment: "Sidebar section"))
            }
            SidebarLocationsSection()
            SidebarTripsSection()
        }
        .listStyle(.sidebar)
        // The design's paper, opaque, instead of the default translucent sidebar.
        .scrollContentBackground(.hidden)
        .background(IterColor.backgroundWindow)
        .snapshotOpaqueBackground()
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SidebarBottomBar()
        }
    }
}
