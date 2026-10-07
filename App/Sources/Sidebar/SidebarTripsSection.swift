import SwiftUI
import IterCore
import IterData
import IterDesign
import IterFeatures

/// The Trips section: All Trips, pinned trips, folders (open and close, not selectable), then unfiled trips.
struct SidebarTripsSection: View {
    @Environment(AppModel.self) private var model
    let expansion: FolderExpansion

    var body: some View {
        let _ = model.store.revision
        let store = model.store
        Section {
            AllTripsRow()
            ForEach(store.pinnedTrips(), id: \.id) { trip in
                SidebarTripRow(trip: trip)
            }
            ForEach(store.folders(kind: .trips), id: \.id) { folder in
                TripsFolderRow(folder: folder, expansion: expansion)
            }
            ForEach(store.trips(in: nil).filter { !$0.isPinned }, id: \.id) { trip in
                SidebarTripRow(trip: trip)
            }
        } header: {
            Text("Trips", comment: "Sidebar section")
        }
    }
}

private struct AllTripsRow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Label(String(localized: "All Trips", comment: "Sidebar item"), systemImage: "map")
            .libraryDrop { LibraryDrops(model: model).onAllTrips($0) }
            .tag(SidebarItem.trips)
    }
}

/// One trip. Pinned trips show here only in the pinned group (above the folders), never inside their folder.
struct SidebarTripRow: View {
    @Environment(AppModel.self) private var model
    let trip: TripRecord

    var body: some View {
        RenamableLabel(id: trip.id, title: trip.name, symbol: "point.topleft.down.to.point.bottomright.curvepath",
                       rename: { model.store.renameTrip(trip, to: $0) }) {
            if trip.isPinned {
                Image(systemName: "pin.fill")
                    .font(.caption2)
                    .foregroundStyle(IterColor.textSecondary)
                    .help(Text("Pinned: kept ready offline", comment: "Tooltip"))
                    .accessibilityLabel(Text("Pinned", comment: "VoiceOver: a pinned trip"))
            }
            OfflineStatusBadge(tripID: trip.id)
        }
        .draggable(LibraryDragItem.trip(trip.id))
        .libraryDrop { LibraryDrops(model: model).onTripRow($0, before: trip) }
        .contextMenu { TripContextMenu(trip: trip) }
        .tag(SidebarItem.trip(trip.id))
    }
}

/// A trips folder: a disclosure group of subfolders then trips. The row opens and closes; it is not a destination.
private struct TripsFolderRow: View {
    @Environment(AppModel.self) private var model
    let folder: FolderRecord
    let expansion: FolderExpansion

    var body: some View {
        let store = model.store
        DisclosureGroup(isExpanded: expansion.binding(for: folder.id)) {
            ForEach(store.subfolders(of: folder), id: \.id) { sub in
                TripsFolderRow(folder: sub, expansion: expansion)
            }
            ForEach(store.trips(in: folder).filter { !$0.isPinned }, id: \.id) { trip in
                SidebarTripRow(trip: trip)
            }
        } label: {
            FolderLabel(folder: folder)
                .contentShape(Rectangle())
                .onTapGesture { expansion.set(folder.id, !expansion.isExpanded(folder.id)) }
                .draggable(LibraryDragItem.folder(folder.id))
                .libraryDrop { LibraryDrops(model: model).onTripsFolder($0, folder) }
                .contextMenu { FolderContextMenu(folder: folder) }
        }
    }
}

/// The folder glyph and name, with inline rename.
struct FolderLabel: View {
    @Environment(AppModel.self) private var model
    let folder: FolderRecord

    var body: some View {
        RenamableLabel(id: folder.id, title: folder.name, symbol: "folder",
                       rename: { model.store.renameFolder(folder, to: $0) }) {}
    }
}
