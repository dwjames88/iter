import SwiftUI
import IterCore
import IterData
import IterDesign
import IterFeatures

/// The Locations section: All Locations, then the locations and location folders pinned to the sidebar. Folders are
/// managed in All Locations.
struct SidebarLocationsSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let _ = model.store.revision
        let store = model.store
        Section {
            Label(String(localized: "All Locations", comment: "Sidebar item"), systemImage: "mappin.and.ellipse")
                .tag(SidebarItem.locations)
            ForEach(store.pinnedPlaces(), id: \.id) { place in
                SidebarPlaceRow(place: place)
            }
            ForEach(store.pinnedFolders(kind: .locations), id: \.id) { folder in
                SidebarFolderRow(folder: folder, item: .locationFolder(folder.id))
            }
        } header: {
            Text("Locations", comment: "Sidebar section")
        }
    }
}

/// A pinned location: opens its spot page. Open and Unpin from its menu.
private struct SidebarPlaceRow: View {
    @Environment(AppModel.self) private var model
    @Environment(AppNavigation.self) private var navigation
    let place: PlaceRecord

    var body: some View {
        Label(place.name, systemImage: "mappin")
            .lineLimit(1)
            .contextMenu {
                Button { navigation.show(.location(place.id)) } label: {
                    Label(String(localized: "Open", comment: "Context menu"), systemImage: "arrow.right.circle")
                }
                Button { model.store.setPinned(place, false) } label: {
                    Label(String(localized: "Unpin from Sidebar", comment: "Context menu"), systemImage: "pin.slash")
                }
            }
            .tag(SidebarItem.location(place.id))
    }
}
