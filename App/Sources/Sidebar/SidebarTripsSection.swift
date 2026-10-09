import SwiftUI
import IterCore
import IterData
import IterDesign
import IterFeatures

/// The Trips section: All Trips, then the trips and trip folders pinned to the sidebar. Folders are managed in All Trips.
struct SidebarTripsSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let _ = model.store.revision
        let store = model.store
        Section {
            Label(String(localized: "All Trips", comment: "Sidebar item"), systemImage: "map")
                .tag(SidebarItem.trips)
            ForEach(store.pinnedTrips(), id: \.id) { trip in
                SidebarTripRow(trip: trip)
            }
            ForEach(store.pinnedFolders(kind: .trips), id: \.id) { folder in
                SidebarFolderRow(folder: folder, item: .tripFolder(folder.id))
            }
        } header: {
            Text("Trips", comment: "Sidebar section")
        }
    }
}

/// A pinned trip, with its offline status. Open and Unpin from its menu.
private struct SidebarTripRow: View {
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
        .contextMenu {
            Button { navigation.show(.trip(trip.id)) } label: {
                Label(String(localized: "Open", comment: "Context menu"), systemImage: "arrow.right.circle")
            }
            Button { model.offline.unpin(trip) } label: {
                Label(String(localized: "Unpin Trip", comment: "Context menu"), systemImage: "pin.slash")
            }
            Divider()
            Button(String(localized: "Delete Trip", comment: "Context menu"), role: .destructive) {
                if navigation.selection == .trip(trip.id) { navigation.selection = .trips }
                model.store.deleteTrip(trip)
            }
        }
        .tag(SidebarItem.trip(trip.id))
    }
}

/// A pinned folder (trips or locations): opens it, Unpin in its menu.
struct SidebarFolderRow: View {
    @Environment(AppModel.self) private var model
    @Environment(AppNavigation.self) private var navigation
    let folder: FolderRecord
    let item: SidebarItem

    var body: some View {
        Label(folder.name, systemImage: "folder")
            .lineLimit(1)
            .contextMenu {
                Button { navigation.show(item) } label: {
                    Label(String(localized: "Open", comment: "Context menu"), systemImage: "arrow.right.circle")
                }
                Button { model.store.setPinned(folder, false) } label: {
                    Label(String(localized: "Unpin from Sidebar", comment: "Context menu"), systemImage: "pin.slash")
                }
            }
            .tag(item)
    }
}
