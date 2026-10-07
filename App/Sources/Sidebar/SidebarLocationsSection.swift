import SwiftUI
import IterCore
import IterData
import IterDesign
import IterFeatures

/// The Locations section: All Locations, then location folders. Folders are destinations; subfolders sit inside a
/// disclosure group.
struct SidebarLocationsSection: View {
    @Environment(AppModel.self) private var model
    let expansion: FolderExpansion

    var body: some View {
        let _ = model.store.revision
        Section {
            Label(String(localized: "All Locations", comment: "Sidebar item"), systemImage: "mappin.and.ellipse")
                .libraryDrop { LibraryDrops(model: model).onAllLocations($0) }
                .tag(SidebarItem.locations)
            ForEach(model.store.folders(kind: .locations), id: \.id) { folder in
                LocationsFolderRow(folder: folder, expansion: expansion)
            }
        } header: {
            Text("Locations", comment: "Sidebar section")
        }
    }
}

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
                ForEach(subfolders, id: \.id) { sub in
                    row(sub).tag(SidebarItem.locationFolder(sub.id))
                }
            } label: {
                row(folder)
            }
            .tag(SidebarItem.locationFolder(folder.id))
        }
    }

    private func row(_ folder: FolderRecord) -> some View {
        FolderLabel(folder: folder)
            .draggable(LibraryDragItem.folder(folder.id))
            .libraryDrop { LibraryDrops(model: model).onLocationsFolder($0, folder) }
            .contextMenu { FolderContextMenu(folder: folder) }
    }
}
