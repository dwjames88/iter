import SwiftUI
import IterFeatures
import IterModel
import IterScreens
import IterUI

// OWNER: W3 (screens). The Saved tab: the saved places map and the Saved Places list.

/// The map behind the sheet for the Saved tab: your saved places; a pin opens its page in the sheet.
struct SavedTabMap: View {
    let shell: IOSShell

    var body: some View {
        SavedPhoneMap(places: shell.library.savedPlaces, mapStyle: shell.container.preferences.mapStyle,
                      bottomInset: shell.mapBottomInset) { id in
            shell.appendRoute(.place(id), to: .saved)
            if shell.detent == PhoneSheet.peek { shell.detent = PhoneSheet.half }
        }
        .iterShellEnvironment(shell)
    }
}

/// The Saved tab's root inside the sheet.
struct SavedTabRoot: View {
    let shell: IOSShell
    var body: some View { SavedListHost(shell: shell, folderID: nil) }
}

/// Saved Places, or one folder's places: the list, New Folder, and the Undo toast.
struct SavedListHost: View {
    let shell: IOSShell
    let folderID: UUID?
    @State private var toast: PhoneUndoToast
    @State private var namingFolder = false
    @State private var folderName = ""

    init(shell: IOSShell, folderID: UUID?) {
        self.shell = shell
        self.folderID = folderID
        _toast = State(initialValue: PhoneUndoToast(library: shell.library))
    }

    var body: some View {
        PhoneSavedList(library: shell.library, folderID: folderID, toast: toast) { shell.push($0, from: .saved) }
            .navigationTitle(title)
            .toolbar {
                if folderID == nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button { folderName = ""; namingFolder = true } label: { Label("New Folder", systemImage: "folder.badge.plus") }
                    }
                }
            }
            .alert("New Folder", isPresented: $namingFolder) {
                TextField(text: $folderName) { Text("Name", comment: "Folder name field") }
                Button("Cancel", role: .cancel) {}
                Button("Create") {
                    let name = folderName.trimmingCharacters(in: .whitespacesAndNewlines)
                    _ = shell.library.createFolder(name: name.isEmpty ? String(localized: "New Folder") : name, kind: .locations)
                }
            }
            .phoneUndoToast(toast)
            .iterShellEnvironment(shell)
    }

    private var title: String {
        guard let folderID else { return String(localized: "Saved", comment: "Tab title") }
        return shell.library.placeFolders.first { $0.id == folderID }?.name ?? String(localized: "Folder", comment: "Title")
    }
}
