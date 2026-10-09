import SwiftUI
import IterCore
import IterData
import IterDesign
import IterFeatures

// Location folders inside the Locations screens (Mac and iOS): the Folders rows, their context menu, the name prompt and
// pinning. The sidebar only lists what is pinned; everything that manages folders lives here.

// MARK: - Name prompt

/// What the one folder-name alert is doing.
enum FolderNameRequest: Identifiable, Equatable {
    /// A new location folder, filed with these places.
    case new(filing: [UUID])
    case rename(UUID)

    var id: String {
        switch self {
        case .new(let filing): "new-\(filing.map(\.uuidString).joined(separator: ","))"
        case .rename(let id): "rename-\(id)"
        }
    }
}

private struct LocationFolderNamePrompt: ViewModifier {
    @Environment(AppModel.self) private var model
    @Binding var request: FolderNameRequest?
    @State private var name = ""

    func body(content: Content) -> some View {
        content
            .alert(title, isPresented: Binding(get: { request != nil }, set: { if !$0 { request = nil } }), presenting: request) { request in
                TextField(String(localized: "Name", comment: "Folder name field"), text: $name)
                Button(String(localized: "Cancel", comment: "Button"), role: .cancel) {}
                Button(String(localized: "Save", comment: "Button")) { commit(request) }
            }
            .onChange(of: request) { _, new in
                switch new {
                case .rename(let id): name = model.store.folder(id: id)?.name ?? ""
                case .new: name = ""
                case nil: break
                }
            }
    }

    private var title: String {
        if case .rename = request { String(localized: "Rename Folder", comment: "Alert title") }
        else { String(localized: "New Folder", comment: "Alert title") }
    }

    private func commit(_ request: FolderNameRequest) {
        guard let name = LibraryNaming.cleanedName(name) else { return }
        let store = model.store
        switch request {
        case .new(let filing):
            let unique = LibraryNaming.uniqueName(name, among: store.folders(kind: .locations).map(\.name))
            _ = store.createFolder(name: unique, kind: .locations, places: filing.compactMap { store.place(id: $0) })
        case .rename(let id):
            if let folder = store.folder(id: id) { store.renameFolder(folder, to: name) }
        }
    }
}

extension View {
    /// The alert that names a new location folder or renames one.
    func locationFolderNamePrompt(_ request: Binding<FolderNameRequest?>) -> some View {
        modifier(LocationFolderNamePrompt(request: request))
    }
}

// MARK: - Folders

/// The folders to list on a Locations screen: every folder on All Locations, none inside a folder (folders do not nest).
@MainActor
func locationFolders(in folder: FolderRecord?, store: IterStore) -> [FolderRecord] {
    folder == nil ? store.folders(kind: .locations) : []
}

/// A folder row for a system List: folder glyph, name, a pin mark when pinned, how many locations it holds. Opens the
/// folder; accepts dropped locations.
struct LocationFolderRow: View {
    @Environment(AppModel.self) private var model
    @Environment(AppNavigation.self) private var navigation
    let folder: FolderRecord
    let rename: () -> Void
    let delete: () -> Void
    @State private var targeted = false

    var body: some View {
        let count = model.store.savedPlaces(in: folder).count
        Button { navigation.show(.locationFolder(folder.id)) } label: {
            HStack(spacing: IterSpace.sm) {
                Label(folder.name, systemImage: "folder.fill")
                    .lineLimit(1)
                Spacer(minLength: IterSpace.sm)
                if folder.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(Text("Pinned to sidebar", comment: "VoiceOver: a pinned folder"))
                }
                Text(count, format: .number)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, IterSpace.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text("\(count) locations", comment: "VoiceOver: how many locations a folder holds"))
        .contextMenu { LocationFolderMenu(folder: folder, rename: rename, delete: delete) }
        .dropDestination(for: LibraryDragItem.self) { items, _ in
            LibraryDrops(model: model).onLocationsFolder(items, folder)
        } isTargeted: { targeted = $0 }
        .listRowBackground(targeted ? IterColor.accent.opacity(0.18) : nil)
    }
}

/// Context menu of a folder: Open, Pin to Sidebar, Rename, Delete.
struct LocationFolderMenu: View {
    @Environment(AppModel.self) private var model
    @Environment(AppNavigation.self) private var navigation
    let folder: FolderRecord
    let rename: () -> Void
    let delete: () -> Void

    var body: some View {
        Button { navigation.show(.locationFolder(folder.id)) } label: {
            Label(String(localized: "Open", comment: "Context menu"), systemImage: "arrow.right.circle")
        }
        Button { model.store.setPinned(folder, !folder.isPinned) } label: {
            if folder.isPinned {
                Label(String(localized: "Unpin from Sidebar", comment: "Context menu"), systemImage: "pin.slash")
            } else {
                Label(String(localized: "Pin to Sidebar", comment: "Context menu"), systemImage: "pin")
            }
        }
        Divider()
        Button(action: rename) { Label(String(localized: "Rename…", comment: "Context menu"), systemImage: "pencil") }
        Button(role: .destructive, action: delete) {
            Label(String(localized: "Delete Folder", comment: "Context menu"), systemImage: "trash")
        }
    }
}

/// Pin to Sidebar or Unpin from Sidebar for the chosen locations (unpins only when all of them are pinned).
struct PinLocationsButton: View {
    @Environment(AppModel.self) private var model
    let places: [PlaceRecord]

    var body: some View {
        let allPinned = !places.isEmpty && places.allSatisfy(\.isPinned)
        Button {
            for place in places { model.store.setPinned(place, !allPinned) }
        } label: {
            if allPinned {
                Label(String(localized: "Unpin from Sidebar", comment: "Context menu"), systemImage: "pin.slash")
            } else {
                Label(String(localized: "Pin to Sidebar", comment: "Context menu"), systemImage: "pin")
            }
        }
    }
}
