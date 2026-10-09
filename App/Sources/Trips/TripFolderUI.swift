import SwiftUI
import IterCore
import IterData
import IterDesign
import IterFeatures

/// What the name prompt on the All Trips page is asking for.
enum TripNamePrompt: Identifiable, Equatable {
    /// A new folder, optionally inside `parent`, optionally taking `trip` in at once.
    case newFolder(parent: UUID?, trip: UUID?)
    case renameFolder(UUID)
    case renameTrip(UUID)

    var id: String {
        switch self {
        case .newFolder(let parent, let trip): "new-\(parent?.uuidString ?? "root")-\(trip?.uuidString ?? "none")"
        case .renameFolder(let id): "folder-\(id)"
        case .renameTrip(let id): "trip-\(id)"
        }
    }
}

private struct TripNamePromptModifier: ViewModifier {
    @Environment(AppModel.self) private var model
    @Binding var prompt: TripNamePrompt?
    @State private var text = ""

    func body(content: Content) -> some View {
        content
            .alert(title, isPresented: Binding(get: { prompt != nil }, set: { if !$0 { prompt = nil } })) {
                TextField(placeholder, text: $text)
                Button(String(localized: "Cancel", comment: "Button"), role: .cancel) {}
                Button(confirmTitle) { commit() }
            } message: {
                Text(message)
            }
            .onChange(of: prompt) { _, new in text = new.map(initialText) ?? "" }
    }

    private var title: String {
        switch prompt {
        case .newFolder: String(localized: "New Folder", comment: "Alert title")
        case .renameFolder: String(localized: "Rename Folder", comment: "Alert title")
        case .renameTrip: String(localized: "Rename Trip", comment: "Alert title")
        case nil: ""
        }
    }

    private var message: String {
        switch prompt {
        case .newFolder: String(localized: "Folders group trips on this page.", comment: "Alert message")
        default: ""
        }
    }

    private var placeholder: String {
        switch prompt {
        case .renameTrip: String(localized: "Trip name", comment: "Placeholder")
        default: String(localized: "Folder name", comment: "Placeholder")
        }
    }

    private var confirmTitle: String {
        switch prompt {
        case .newFolder: String(localized: "Create", comment: "Button")
        default: String(localized: "Rename", comment: "Button")
        }
    }

    private func initialText(_ prompt: TripNamePrompt) -> String {
        switch prompt {
        case .newFolder(let parent, _):
            let siblings = parent.flatMap { model.store.folder(id: $0) }.map { model.store.subfolders(of: $0) }
                ?? model.store.folders(kind: .trips)
            return LibraryNaming.uniqueName(String(localized: "New Folder", comment: "Default name of a new folder"),
                                            among: siblings.map(\.name))
        case .renameFolder(let id): return model.store.folder(id: id)?.name ?? ""
        case .renameTrip(let id): return model.store.trip(id: id)?.name ?? ""
        }
    }

    private func commit() {
        guard let prompt, let name = LibraryNaming.cleanedName(text) else { return }
        switch prompt {
        case .newFolder(let parent, let tripID):
            let parentFolder = parent.flatMap { model.store.folder(id: $0) }
            let trips = tripID.flatMap { model.store.trip(id: $0) }.map { [$0] } ?? []
            _ = model.store.createFolder(name: name, kind: .trips, parent: parentFolder, trips: trips)
        case .renameFolder(let id):
            if let folder = model.store.folder(id: id) { model.store.renameFolder(folder, to: name) }
        case .renameTrip(let id):
            if let trip = model.store.trip(id: id) { model.store.renameTrip(trip, to: name) }
        }
    }
}

extension View {
    /// The system alert with a text field that names or renames a trip or a trip folder.
    func tripNamePrompt(_ prompt: Binding<TripNamePrompt?>) -> some View {
        modifier(TripNamePromptModifier(prompt: prompt))
    }
}

// MARK: - Menus

/// Move to Folder for the All Trips page: No Folder, every folder (subfolders under their parent), then New Folder.
struct TripMoveMenu: View {
    @Environment(AppModel.self) private var model
    let trip: TripRecord
    @Binding var prompt: TripNamePrompt?

    var body: some View {
        Menu {
            entry(String(localized: "No Folder", comment: "Move to Folder menu: unfile"), folder: nil, marked: trip.folder == nil)
            let roots = model.store.folders(kind: .trips)
            if !roots.isEmpty { Divider() }
            ForEach(roots, id: \.id) { root in
                entry(root.name, folder: root, marked: trip.folder?.id == root.id)
                ForEach(model.store.subfolders(of: root), id: \.id) { sub in
                    entry(String(localized: "\(root.name) › \(sub.name)", comment: "Move to Folder menu: a subfolder under its folder"),
                          folder: sub, marked: trip.folder?.id == sub.id)
                }
            }
            Divider()
            Button(String(localized: "New Folder…", comment: "Move to Folder menu")) {
                prompt = .newFolder(parent: nil, trip: trip.id)
            }
        } label: {
            Label(String(localized: "Move to Folder", comment: "Context menu"), systemImage: "folder")
        }
    }

    @ViewBuilder private func entry(_ title: String, folder: FolderRecord?, marked: Bool) -> some View {
        Button { model.store.moveTrips([trip], to: folder, index: nil) } label: {
            if marked { Label(title, systemImage: "checkmark") } else { Text(title) }
        }
        .disabled(marked)
    }
}

/// The context menu of a trip card or the hero.
struct TripEntryMenu: View {
    @Environment(AppModel.self) private var model
    @Environment(AppNavigation.self) private var navigation
    let trip: TripRecord
    @Binding var prompt: TripNamePrompt?

    var body: some View {
        Button { navigation.show(.trip(trip.id)) } label: {
            Label(String(localized: "Open", comment: "Context menu"), systemImage: "arrow.up.right.square")
        }
        if trip.isPinned {
            Button { model.offline.unpin(trip) } label: {
                Label(String(localized: "Unpin Trip", comment: "Context menu"), systemImage: "pin.slash")
            }
        } else {
            Button { _ = model.offline.pin(trip) } label: {
                Label(String(localized: "Pin Trip", comment: "Context menu: keeps the trip downloaded for offline use"), systemImage: "pin")
            }
        }
        Divider()
        TripMoveMenu(trip: trip, prompt: $prompt)
        Button { prompt = .renameTrip(trip.id) } label: {
            Label(String(localized: "Rename…", comment: "Context menu"), systemImage: "pencil")
        }
        Button {
            let copy = model.store.duplicateTrip(trip, name: String(localized: "\(trip.name) copy", comment: "Name of a duplicated trip"))
            navigation.show(.trip(copy.id))
        } label: {
            Label(String(localized: "Duplicate", comment: "Context menu"), systemImage: "plus.square.on.square")
        }
        ShareLink(item: model.store.document(for: trip), preview: SharePreview(trip.name)) {
            Label(String(localized: "Share…", comment: "Context menu"), systemImage: "square.and.arrow.up")
        }
        Divider()
        Button(role: .destructive) { model.store.deleteTrip(trip) } label: {
            Label(String(localized: "Delete Trip", comment: "Context menu"), systemImage: "trash")
        }
    }
}

/// The menu on a folder's header: rename, pin to the sidebar, add a folder, delete (its trips move up).
struct TripFolderMenu: View {
    @Environment(AppModel.self) private var model
    @Environment(AppNavigation.self) private var navigation
    let folderID: UUID
    @Binding var prompt: TripNamePrompt?

    var body: some View {
        let folder = model.store.folder(id: folderID)
        Button { prompt = .renameFolder(folderID) } label: {
            Label(String(localized: "Rename Folder…", comment: "Folder menu"), systemImage: "pencil")
        }
        if let folder {
            Button { model.store.setPinned(folder, !folder.isPinned) } label: {
                folder.isPinned
                    ? Label(String(localized: "Unpin from Sidebar", comment: "Folder menu"), systemImage: "pin.slash")
                    : Label(String(localized: "Pin to Sidebar", comment: "Folder menu"), systemImage: "pin")
            }
        }
        Button { prompt = .newFolder(parent: nil, trip: nil) } label: {
            Label(String(localized: "New Folder…", comment: "Folder menu"), systemImage: "folder.badge.plus")
        }
        Divider()
        Button(role: .destructive) {
            if navigation.selection == .tripFolder(folderID) { navigation.selection = .trips }
            if let folder { model.store.deleteFolder(folder) }
        } label: {
            Label(String(localized: "Delete Folder", comment: "Folder menu: its trips move up, none are deleted"), systemImage: "trash")
        }
    }
}
