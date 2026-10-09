import SwiftUI
import IterCore
import IterData
import IterFeatures

/// "Move to Folder" submenu: No Folder, then every folder of the kind. The current folder is
/// checked and disabled.
struct MoveToFolderMenu: View {
    @Environment(AppModel.self) private var model
    let kind: FolderKind
    /// The folder everything chosen already sits in; nil with `inNoFolder` false = mixed, nothing is marked.
    var currentFolderID: UUID?
    var inNoFolder = false
    let move: (FolderRecord?) -> Void

    var body: some View {
        Menu {
            entry(String(localized: "No Folder", comment: "Move to Folder menu: unfile"), folder: nil, marked: inNoFolder)
            let folders = model.store.folders(kind: kind)
            if !folders.isEmpty { Divider() }
            ForEach(folders, id: \.id) { folder in
                entry(folder.name, folder: folder, marked: currentFolderID == folder.id)
            }
        } label: {
            Label(String(localized: "Move to Folder", comment: "Context menu"), systemImage: "folder")
        }
    }

    @ViewBuilder private func entry(_ title: String, folder: FolderRecord?, marked: Bool) -> some View {
        Button { move(folder) } label: {
            if marked { Label(title, systemImage: "checkmark") } else { Text(title) }
        }
        .disabled(marked)
    }
}

/// Shared context menu for a trip (sidebar and the trips overview).
struct TripContextMenu: View {
    @Environment(AppModel.self) private var model
    @Environment(AppNavigation.self) private var navigation
    let trip: TripRecord

    var body: some View {
        Button(String(localized: "Open", comment: "Context menu")) { navigation.show(.trip(trip.id)) }
        if trip.isPinned {
            Button { model.offline.unpin(trip) } label: {
                Label(String(localized: "Unpin Trip", comment: "Context menu"), systemImage: "pin.slash")
            }
        } else {
            Button { model.offline.pin(trip) } label: {
                Label(String(localized: "Pin Trip", comment: "Context menu: keeps the trip downloaded for offline use"), systemImage: "pin")
            }
        }
        Divider()
        MoveToFolderMenu(kind: .trips, currentFolderID: trip.folder?.id, inNoFolder: trip.folder == nil) { folder in
            model.store.moveTrips([trip], to: folder, index: nil)
        }
        Button(String(localized: "New Folder with Selection", comment: "Context menu")) {
            navigation.newFolder(model: model, kind: .trips, trips: [trip])
        }
        Button(String(localized: "Rename", comment: "Context menu")) { navigation.renamingID = trip.id }
        Divider()
        Button(String(localized: "Duplicate", comment: "Context menu")) {
            let copy = model.store.duplicateTrip(trip, name: String(localized: "\(trip.name) copy", comment: "Name of a duplicated trip"))
            navigation.show(.trip(copy.id))
        }
        ShareLink(item: model.store.document(for: trip), preview: SharePreview(trip.name)) {
            Text("Share…", comment: "Context menu")
        }
        Divider()
        Button(String(localized: "Delete Trip", comment: "Context menu"), role: .destructive) {
            if navigation.selection == .trip(trip.id) { navigation.selection = .trips }
            model.store.deleteTrip(trip)
        }
    }
}
