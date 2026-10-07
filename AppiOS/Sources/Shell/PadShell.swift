import SwiftUI
import IterCore
import IterData
import IterFeatures

/// iPad in regular width: the split view with the sidebar, as on the Mac (plan 6.1-A: the tab bar becomes a sidebar).
/// The detail column follows `navigation.selection` exactly like the Mac's `DetailView`.
struct PadShell: View {
    @Environment(AppNavigation.self) private var navigation
    @Environment(ShellState.self) private var shell

    var body: some View {
        @Bindable var shell = shell
        NavigationSplitView {
            PadSidebar()
        } detail: {
            PadDetail()
        }
        .onAppear { shell.usesTabs = false }
        .sheet(isPresented: $shell.showsSettingsSheet) {
            NavigationStack {
                IOSSettingsScreen()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(String(localized: "Done", comment: "Button")) { shell.showsSettingsSheet = false }
                        }
                    }
            }
        }
    }
}

/// The sidebar: Trips (All Trips, pinned, folders), Locations (All Locations, folders), Find (Explore).
struct PadSidebar: View {
    @Environment(AppModel.self) private var model
    @Environment(AppNavigation.self) private var navigation
    @Environment(ShellState.self) private var shell

    var body: some View {
        @Bindable var navigation = navigation
        let _ = model.store.revision
        List(selection: $navigation.selection) {
            Section(String(localized: "Trips", comment: "Sidebar section")) {
                Label(String(localized: "All Trips", comment: "Sidebar row"), systemImage: "car.side").tag(SidebarItem.trips)
                ForEach(model.store.pinnedTrips(), id: \.id) { trip in
                    Label(trip.name, systemImage: "pin").tag(SidebarItem.trip(trip.id))
                }
                ForEach(model.store.trips(in: nil).filter { !$0.isPinned }, id: \.id) { trip in
                    Label(trip.name, systemImage: "map").tag(SidebarItem.trip(trip.id))
                }
                ForEach(model.store.folders(kind: .trips), id: \.id) { folder in
                    DisclosureGroup {
                        ForEach(model.store.trips(in: folder).filter { !$0.isPinned }, id: \.id) { trip in
                            Label(trip.name, systemImage: "map").tag(SidebarItem.trip(trip.id))
                        }
                    } label: {
                        Label(folder.name, systemImage: "folder")
                    }
                }
            }
            Section(String(localized: "Locations", comment: "Sidebar section")) {
                Label(String(localized: "All Locations", comment: "Sidebar row"), systemImage: "mappin.and.ellipse").tag(SidebarItem.locations)
                ForEach(model.store.folders(kind: .locations), id: \.id) { folder in
                    Label(folder.name, systemImage: "folder").tag(SidebarItem.locationFolder(folder.id))
                }
            }
            Section(String(localized: "Find", comment: "Sidebar section")) {
                Label(String(localized: "Explore", comment: "Sidebar row"), systemImage: "map").tag(SidebarItem.explore)
            }
        }
        .navigationTitle(String(localized: "Iter", comment: "Sidebar title"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { shell.showSettings() } label: {
                    Label(String(localized: "Settings", comment: "Button"), systemImage: "gearshape")
                }
            }
        }
    }
}

/// The detail column for the sidebar selection; each section keeps its own stack in `AppNavigation`.
struct PadDetail: View {
    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        @Bindable var navigation = navigation
        switch navigation.selection {
        case .trips, nil:
            NavigationStack(path: $navigation.tripPath) { TripsListScreen().iosSpotDestination() }
        case .trip(let id):
            NavigationStack(path: $navigation.tripPath) { TripBuilderScreen(tripID: id).iosSpotDestination() }.id(id)
        case .explore:
            NavigationStack(path: $navigation.explorePath) { PadExploreScreen().iosSpotDestination() }
        case .locations:
            NavigationStack(path: $navigation.locationsPath) { LocationsScreen(folderID: nil).iosSpotDestination() }.id("all-locations")
        case .locationFolder(let id):
            NavigationStack(path: $navigation.locationsPath) { LocationsScreen(folderID: id).iosSpotDestination() }.id(id)
        }
    }
}
