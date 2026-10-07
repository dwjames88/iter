import SwiftUI
import IterCore
import IterData
import IterDesign
import IterFeatures

/// The sidebar: Trips (pinned trips and folders), Locations (folders) and Find. A system source list; the sections
/// are in their own files.
struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppNavigation.self) private var navigation
    @AppStorage("sidebar.expandedFolders") private var expandedRaw = ""

    var body: some View {
        @Bindable var navigation = navigation
        let expansion = FolderExpansion(raw: $expandedRaw)
        List(selection: $navigation.selection) {
            SidebarTripsSection(expansion: expansion)
            SidebarLocationsSection(expansion: expansion)
            Section {
                Label(String(localized: "Explore", comment: "Sidebar item"), systemImage: "binoculars")
                    .tag(SidebarItem.explore)
            } header: {
                Text("Find", comment: "Sidebar section")
            }
        }
        .listStyle(.sidebar)
        .snapshotOpaqueBackground()
        .safeAreaInset(edge: .bottom) {
            if model.sampleDataEnabled {
                SampleDataLabel(style: .banner).padding(IterSpace.sm)
            }
        }
        .toolbar {
            ToolbarItem {
                addMenu
            }
        }
        // A row about to be renamed must be visible: open the folders it sits in.
        .onChange(of: navigation.renamingID) { _, id in reveal(id, expansion) }
    }

    private var addMenu: some View {
        Menu {
            Button(String(localized: "New Trip", comment: "Menu item")) {
                navigation.newTripRequest += 1
                if case .trip = navigation.selection {} else { navigation.selection = .trips }
            }
            Button(String(localized: "New Folder", comment: "Menu item")) { navigation.newFolder(model: model) }
            Button(String(localized: "New Location", comment: "Menu item: drops a pin on the Explore map")) {
                navigation.show(.explore)
                navigation.addSpotModeRequest += 1
            }
        } label: {
            Label(String(localized: "New", comment: "Toolbar button"), systemImage: "plus")
        }
        .menuIndicator(.hidden)
        .help(Text("New Trip, Folder or Location", comment: "Tooltip"))
    }

    private func reveal(_ id: UUID?, _ expansion: FolderExpansion) {
        guard let id else { return }
        if let renamed = model.store.folder(id: id) {
            if let parent = renamed.parent { expansion.set(parent.id, true) }
        } else if let folder = model.store.trip(id: id)?.folder {
            expansion.set(folder.id, true)
            if let parent = folder.parent { expansion.set(parent.id, true) }
        }
    }
}
