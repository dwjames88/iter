import SwiftUI
import IterFeatures
import IterModel
import IterScreens
import IterUI

// OWNER: W3 (screens). The Trips tab: the map behind the sheet and the All Trips list.

/// The map behind the sheet for the Trips tab: the open trip's route when one is pushed, otherwise your saved places (what trips are
/// built from); a pin opens its page.
struct TripsTabMap: View {
    let shell: IOSShell

    var body: some View {
        Group {
            if let id = shell.openTripID {
                TripPhoneMap(model: shell.buildModel(for: id), mapStyle: shell.container.preferences.mapStyle, bottomInset: shell.mapBottomInset)
            } else {
                SavedPhoneMap(places: shell.library.savedPlaces, mapStyle: shell.container.preferences.mapStyle,
                              bottomInset: shell.mapBottomInset) { shell.appendRoute(.place($0), to: .trips) }
            }
        }
        .iterShellEnvironment(shell)
        .ignoresSafeArea()
    }
}

/// The Trips tab's root inside the sheet.
struct TripsTabRoot: View {
    let shell: IOSShell
    var body: some View { TripsListHost(shell: shell, folderID: nil) }
}

/// All Trips, or one folder's trips: the list, its toolbar (New Trip, More), the Undo toast and the New Folder prompt.
struct TripsListHost: View {
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
        PhoneTripsList(library: shell.library, folderID: folderID, toast: toast, open: { shell.push($0, from: .trips) }) { id in
            ShareTripButton(tripID: id, library: shell.library)
        }
        .environment(\.libraryLightScore, shell.lightScore)
        .navigationTitle(title)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { shell.navigator.present(.newTrip(templateID: nil, firstPlace: nil)) } label: { Label("New Trip", systemImage: "plus") }
                Menu {
                    Button { folderName = ""; namingFolder = true } label: { Label("New Folder", systemImage: "folder.badge.plus") }
                    Button { shell.sharing.beginImport() } label: { Label("Import Trips", systemImage: "square.and.arrow.down") }
                    ShareLibraryButton(library: shell.library)
                } label: { Label("More", systemImage: "ellipsis") }
            }
        }
        .alert("New Folder", isPresented: $namingFolder) {
            TextField(text: $folderName) { Text("Name", comment: "Folder name field") }
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                let name = folderName.trimmingCharacters(in: .whitespacesAndNewlines)
                _ = shell.library.createFolder(name: name.isEmpty ? String(localized: "New Folder") : name, kind: .trips)
            }
        }
        .phoneUndoToast(toast)
        .iterShellEnvironment(shell)
    }

    private var title: String {
        guard let folderID else { return String(localized: "Trips", comment: "Tab title") }
        return shell.library.tripFolders.first { $0.id == folderID }?.name ?? String(localized: "Folder", comment: "Title")
    }
}
