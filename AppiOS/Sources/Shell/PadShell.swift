import SwiftUI
import IterCore
import IterData
import IterDesign
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

/// The sidebar, as the Mac's: Trips and Locations (each: its "All" page, then what is pinned) and Find (Explore).
/// Folders are managed inside All Trips and All Locations, not here.
struct PadSidebar: View {
    @Environment(AppModel.self) private var model
    @Environment(AppNavigation.self) private var navigation
    @Environment(ShellState.self) private var shell
    @State private var showsNewTrip = false

    var body: some View {
        @Bindable var navigation = navigation
        let _ = model.store.revision
        let store = model.store
        List(selection: $navigation.selection) {
            Section(String(localized: "Trips", comment: "Sidebar section")) {
                Label(String(localized: "All Trips", comment: "Sidebar row"), systemImage: "map").tag(SidebarItem.trips)
                ForEach(store.pinnedTrips(), id: \.id) { trip in PadTripRow(trip: trip) }
                ForEach(store.pinnedFolders(kind: .trips), id: \.id) { folder in
                    PadFolderRow(folder: folder, item: .tripFolder(folder.id))
                }
            }
            Section(String(localized: "Locations", comment: "Sidebar section")) {
                Label(String(localized: "All Locations", comment: "Sidebar row"), systemImage: "mappin.and.ellipse").tag(SidebarItem.locations)
                ForEach(store.pinnedPlaces(), id: \.id) { place in PadPlaceRow(place: place) }
                ForEach(store.pinnedFolders(kind: .locations), id: \.id) { folder in
                    PadFolderRow(folder: folder, item: .locationFolder(folder.id))
                }
            }
            Section(String(localized: "Find", comment: "Sidebar section")) {
                Label(String(localized: "Explore", comment: "Sidebar row"), systemImage: "binoculars").tag(SidebarItem.explore)
            }
        }
        .navigationTitle(String(localized: "Iter", comment: "Sidebar title"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showsNewTrip = true } label: { Label(String(localized: "New Trip", comment: "Toolbar button"), systemImage: "plus") }
            }
            ToolbarItem(placement: .bottomBar) {
                Button { shell.showSettings() } label: {
                    Label(String(localized: "Settings", comment: "Button"), systemImage: "gearshape")
                }
            }
        }
        .sheet(isPresented: $showsNewTrip) {
            NewTripSheet(initialStart: model.today(in: .current).adding(days: 1))
        }
    }
}

/// A pinned trip: name and offline status. Open and Unpin from its menu or a swipe.
private struct PadTripRow: View {
    @Environment(AppModel.self) private var model
    @Environment(AppNavigation.self) private var navigation
    let trip: TripRecord

    var body: some View {
        Label {
            HStack(spacing: IterSpace.xs) {
                Text(trip.name).lineLimit(1)
                Spacer(minLength: 0)
                OfflineStatusBadge(tripID: trip.id)
            }
        } icon: {
            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
        }
        .tag(SidebarItem.trip(trip.id))
        .contextMenu {
            Button { navigation.show(.trip(trip.id)) } label: {
                Label(String(localized: "Open", comment: "Context menu"), systemImage: "arrow.right.circle")
            }
            Button { model.offline.unpin(trip) } label: {
                Label(String(localized: "Unpin Trip", comment: "Context menu"), systemImage: "pin.slash")
            }
            Divider()
            Button(String(localized: "Delete Trip", comment: "Context menu"), role: .destructive) { delete() }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { delete() } label: { Label(String(localized: "Delete", comment: "Swipe action"), systemImage: "trash") }
            Button { model.offline.unpin(trip) } label: { Label(String(localized: "Unpin", comment: "Swipe action"), systemImage: "pin.slash") }
                .tint(IterColor.textSecondary)
        }
    }

    private func delete() {
        if navigation.selection == .trip(trip.id) { navigation.selection = .trips }
        model.store.deleteTrip(trip)
    }
}

/// A pinned folder (trips or locations).
private struct PadFolderRow: View {
    @Environment(AppModel.self) private var model
    @Environment(AppNavigation.self) private var navigation
    let folder: FolderRecord
    let item: SidebarItem

    var body: some View {
        Label(folder.name, systemImage: "folder")
            .lineLimit(1)
            .tag(item)
            .contextMenu {
                Button { navigation.show(item) } label: {
                    Label(String(localized: "Open", comment: "Context menu"), systemImage: "arrow.right.circle")
                }
                Button { model.store.setPinned(folder, false) } label: {
                    Label(String(localized: "Unpin from Sidebar", comment: "Context menu"), systemImage: "pin.slash")
                }
            }
            .swipeActions(edge: .trailing) {
                Button { model.store.setPinned(folder, false) } label: { Label(String(localized: "Unpin", comment: "Swipe action"), systemImage: "pin.slash") }
                    .tint(IterColor.textSecondary)
            }
    }
}

/// A pinned location: opens its spot page.
private struct PadPlaceRow: View {
    @Environment(AppModel.self) private var model
    @Environment(AppNavigation.self) private var navigation
    let place: PlaceRecord

    var body: some View {
        Label(place.name, systemImage: "mappin")
            .lineLimit(1)
            .tag(SidebarItem.location(place.id))
            .contextMenu {
                Button { navigation.show(.location(place.id)) } label: {
                    Label(String(localized: "Open", comment: "Context menu"), systemImage: "arrow.right.circle")
                }
                Button { model.store.setPinned(place, false) } label: {
                    Label(String(localized: "Unpin from Sidebar", comment: "Context menu"), systemImage: "pin.slash")
                }
            }
            .swipeActions(edge: .trailing) {
                Button { model.store.setPinned(place, false) } label: { Label(String(localized: "Unpin", comment: "Swipe action"), systemImage: "pin.slash") }
                    .tint(IterColor.textSecondary)
            }
    }
}

/// The detail column for the sidebar selection; each section keeps its own stack in `AppNavigation`.
struct PadDetail: View {
    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        @Bindable var navigation = navigation
        switch navigation.selection {
        case .trips, .tripFolder, nil:
            NavigationStack(path: $navigation.tripPath) { TripsListScreen().iosSpotDestination() }
        case .trip(let id):
            NavigationStack(path: $navigation.tripPath) { TripBuilderScreen(tripID: id).iosSpotDestination() }.id(id)
        case .explore:
            NavigationStack(path: $navigation.explorePath) { PadExploreScreen().iosSpotDestination() }
        case .locations:
            NavigationStack(path: $navigation.locationsPath) { LocationsScreen(folderID: nil).iosSpotDestination() }.id("all-locations")
        case .locationFolder(let id):
            NavigationStack(path: $navigation.locationsPath) { LocationsScreen(folderID: id).iosSpotDestination() }.id(id)
        case .location(let id):
            NavigationStack(path: $navigation.locationsPath) { PinnedLocationScreen(placeID: id).iosSpotDestination() }.id(id)
        }
    }
}

/// A location pinned to the sidebar: its spot page.
private struct PinnedLocationScreen: View {
    @Environment(AppModel.self) private var model
    let placeID: UUID

    var body: some View {
        if let place = model.store.place(id: placeID) {
            SpotPageScreen(route: SpotRoute(spot: place.spot))
        } else {
            ContentUnavailableView(String(localized: "Location not found", comment: "Empty title"), systemImage: "mappin.slash")
        }
    }
}
