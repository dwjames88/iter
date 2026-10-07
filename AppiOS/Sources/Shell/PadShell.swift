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

/// The sidebar, as the Mac's: Trips (All Trips, pinned trips with their offline badge, folders and subfolders as disclosure
/// groups, then unfiled trips), Locations (All Locations, folders and subfolders), Find (Explore).
struct PadSidebar: View {
    @Environment(AppModel.self) private var model
    @Environment(AppNavigation.self) private var navigation
    @Environment(ShellState.self) private var shell
    @AppStorage("IterExpandedFolders") private var expandedRaw = ""
    @State private var renaming: Renaming?
    @State private var renameText = ""
    @State private var showsNewTrip = false

    private enum Renaming: Identifiable {
        case trip(UUID), folder(UUID)
        var id: UUID { switch self { case .trip(let id), .folder(let id): id } }
    }

    private var expansion: FolderExpansion { FolderExpansion(raw: $expandedRaw) }

    var body: some View {
        @Bindable var navigation = navigation
        let _ = model.store.revision
        let store = model.store
        List(selection: $navigation.selection) {
            Section(String(localized: "Trips", comment: "Sidebar section")) {
                Label(String(localized: "All Trips", comment: "Sidebar row"), systemImage: "map").tag(SidebarItem.trips)
                ForEach(store.pinnedTrips(), id: \.id) { trip in tripRow(trip) }
                ForEach(store.folders(kind: .trips), id: \.id) { folder in TripsFolderRow(folder: folder, expansion: expansion) }
                ForEach(store.trips(in: nil).filter { !$0.isPinned }, id: \.id) { trip in tripRow(trip) }
            }
            Section(String(localized: "Locations", comment: "Sidebar section")) {
                Label(String(localized: "All Locations", comment: "Sidebar row"), systemImage: "mappin.and.ellipse").tag(SidebarItem.locations)
                ForEach(store.folders(kind: .locations), id: \.id) { folder in LocationsFolderRow(folder: folder, expansion: expansion) }
            }
            Section(String(localized: "Find", comment: "Sidebar section")) {
                Label(String(localized: "Explore", comment: "Sidebar row"), systemImage: "binoculars").tag(SidebarItem.explore)
            }
        }
        .navigationTitle(String(localized: "Iter", comment: "Sidebar title"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showsNewTrip = true } label: { Label(String(localized: "New Trip", comment: "Menu item"), systemImage: "plus") }
                    Button { navigation.newFolder(model: model) } label: {
                        Label(String(localized: "New Folder", comment: "Menu item"), systemImage: "folder.badge.plus")
                    }
                } label: { Label(String(localized: "New", comment: "Toolbar menu"), systemImage: "plus") }
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
        // `TripContextMenu`, `FolderContextMenu` and New Folder ask for an in-place rename through `renamingID`; on iOS that is an alert.
        .onChange(of: navigation.renamingID) { _, id in
            guard let id else { return }
            navigation.renamingID = nil
            if let trip = store.trip(id: id) {
                renameText = trip.name
                renaming = .trip(id)
            } else if let folder = store.folder(id: id) {
                renameText = folder.name
                renaming = .folder(id)
            }
        }
        .alert(String(localized: "Rename", comment: "Alert title"), isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField(String(localized: "Name", comment: "Rename field"), text: $renameText)
            Button(String(localized: "Cancel", comment: "Button"), role: .cancel) {}
            Button(String(localized: "Save", comment: "Button")) { commitRename() }
        }
    }

    private func commitRename() {
        guard let name = LibraryNaming.cleanedName(renameText) else { return }
        switch renaming {
        case .trip(let id): if let trip = model.store.trip(id: id) { model.store.renameTrip(trip, to: name) }
        case .folder(let id): if let folder = model.store.folder(id: id) { model.store.renameFolder(folder, to: name) }
        case nil: break
        }
    }

    private func tripRow(_ trip: TripRecord) -> some View { PadTripRow(trip: trip) }
}

/// One trip: name, a pin mark when pinned, and its offline status.
private struct PadTripRow: View {
    @Environment(AppModel.self) private var model
    @Environment(AppNavigation.self) private var navigation
    let trip: TripRecord

    var body: some View {
        Label {
            HStack(spacing: IterSpace.xs) {
                Text(trip.name).lineLimit(1)
                Spacer(minLength: 0)
                if trip.isPinned {
                    Image(systemName: "pin.fill").font(.caption2).foregroundStyle(IterColor.textSecondary)
                        .accessibilityLabel(Text("Pinned", comment: "VoiceOver: a pinned trip"))
                }
                OfflineStatusBadge(tripID: trip.id)
            }
        } icon: {
            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
        }
        .tag(SidebarItem.trip(trip.id))
        .contextMenu { TripContextMenu(trip: trip) }
        .swipeActions(edge: .leading) {
            if trip.isPinned {
                Button { model.offline.unpin(trip) } label: { Label(String(localized: "Unpin", comment: "Swipe action"), systemImage: "pin.slash") }
                    .tint(IterColor.textSecondary)
            } else {
                Button { model.offline.pin(trip) } label: { Label(String(localized: "Pin", comment: "Swipe action"), systemImage: "pin") }
                    .tint(IterColor.accent)
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                if navigation.selection == .trip(trip.id) { navigation.selection = .trips }
                model.store.deleteTrip(trip)
            } label: { Label(String(localized: "Delete", comment: "Swipe action"), systemImage: "trash") }
            Button { navigation.renamingID = trip.id } label: { Label(String(localized: "Rename", comment: "Swipe action"), systemImage: "pencil") }
                .tint(IterColor.textSecondary)
        }
    }
}

/// A trips folder: subfolders, then trips. The row opens and closes; it is not a destination.
private struct TripsFolderRow: View {
    @Environment(AppModel.self) private var model
    let folder: FolderRecord
    let expansion: FolderExpansion

    var body: some View {
        let store = model.store
        DisclosureGroup(isExpanded: expansion.binding(for: folder.id)) {
            ForEach(store.subfolders(of: folder), id: \.id) { sub in TripsFolderRow(folder: sub, expansion: expansion) }
            ForEach(store.trips(in: folder).filter { !$0.isPinned }, id: \.id) { trip in PadTripRow(trip: trip) }
        } label: {
            Label(folder.name, systemImage: "folder")
                .contextMenu { FolderContextMenu(folder: folder) }
                .swipeActions(edge: .trailing) { folderSwipes(folder) }
        }
    }
}

/// A locations folder; with subfolders it is a disclosure group and still a destination.
private struct LocationsFolderRow: View {
    @Environment(AppModel.self) private var model
    let folder: FolderRecord
    let expansion: FolderExpansion

    var body: some View {
        let subfolders = model.store.subfolders(of: folder)
        if subfolders.isEmpty {
            row(folder).tag(SidebarItem.locationFolder(folder.id))
        } else {
            DisclosureGroup(isExpanded: expansion.binding(for: folder.id)) {
                ForEach(subfolders, id: \.id) { sub in row(sub).tag(SidebarItem.locationFolder(sub.id)) }
            } label: {
                row(folder)
            }
            .tag(SidebarItem.locationFolder(folder.id))
        }
    }

    private func row(_ folder: FolderRecord) -> some View {
        Label(folder.name, systemImage: "folder")
            .contextMenu { FolderContextMenu(folder: folder) }
            .swipeActions(edge: .trailing) { folderSwipes(folder) }
    }
}

/// Delete and Rename swipes for a folder row (the delete is undoable through the store).
@ViewBuilder @MainActor private func folderSwipes(_ folder: FolderRecord) -> some View {
    FolderSwipeButtons(folder: folder)
}

private struct FolderSwipeButtons: View {
    @Environment(AppModel.self) private var model
    @Environment(AppNavigation.self) private var navigation
    let folder: FolderRecord

    var body: some View {
        Button(role: .destructive) {
            if navigation.selection == .locationFolder(folder.id) { navigation.selection = .locations }
            model.store.deleteFolder(folder)
        } label: { Label(String(localized: "Delete", comment: "Swipe action"), systemImage: "trash") }
        Button { navigation.renamingID = folder.id } label: { Label(String(localized: "Rename", comment: "Swipe action"), systemImage: "pencil") }
            .tint(IterColor.textSecondary)
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
