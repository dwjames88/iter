import SwiftUI
import IterFeatures
import IterScreens

/// The menu bar, with the old shortcuts for every feature that still exists. Context comes from the focused window's
/// `WindowShell` (a scene value), so a command is disabled when no main window is key. Undo and Redo are the system's: they
/// act on the window's undo manager, which the shell hands to the store, so they read "Undo Move Stop" and the like.
struct ShellCommands: Commands {
    let shell: AppShell?
    @FocusedValue(\.windowShell) private var window
    @FocusedValue(\.selectedSavedPlace) private var selectedSavedPlace

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Trip") { window?.newTrip() }
                .keyboardShortcut("n")
                .disabled(window == nil)
            Button("New Folder") { window?.newFolder() }
                .keyboardShortcut("n", modifiers: [.command, .option])
                .disabled(window == nil)
            Button("Add Spot on Map") { window?.addSpot() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(window == nil)
            Divider()
            Button("Import Trip…") { window?.beginImport() }
                .keyboardShortcut("o")
                .disabled(window == nil)
            Button("Export Library…") { window?.exportLibrary() }
                .disabled(window == nil)
            Button("Send Library to iPhone…") { window?.sendLibraryToIPhone() }
                .disabled(window == nil)
        }
        CommandGroup(after: .pasteboard) {
            Button("Edit Place…") { window?.editPlace(selectedSaved: selectedSavedPlace) }
                .keyboardShortcut("e")
                .disabled(window?.editPlaceTarget(selectedSaved: selectedSavedPlace) == nil)
        }
        CommandGroup(after: .textEditing) {
            Button("Find Spots") { window?.findSpots() }
                .keyboardShortcut("f")
                .disabled(window == nil)
            Button("Search Here") { window?.searchHere() }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                .disabled(window == nil)
        }
        CommandGroup(after: .toolbar) {
            Button("Trip Builder") { window?.inspectorShown.toggle() }
                .keyboardShortcut("0", modifiers: [.command, .option])
                .disabled(!(window?.availability.tripCommands ?? false))
            if let shell { MapStyleMenu(preferences: shell.container.preferences) }
        }
        CommandMenu("Go") {
            Button("Find") { window?.navigator.open(.find) }
                .keyboardShortcut("1")
                .disabled(window == nil)
            Button("Trips") { window?.navigator.open(.allTrips) }
                .keyboardShortcut("2")
                .disabled(window == nil)
            Button("Saved Places") { window?.navigator.open(.savedPlaces) }
                .keyboardShortcut("3")
                .disabled(window == nil)
        }
        CommandMenu("Conditions") {
            Button("Refresh") { window?.refreshConditions() }
                .keyboardShortcut("r")
                .disabled(!(window?.availability.refreshConditions ?? false))
        }
        CommandMenu("Trip") {
            Button("Change Dates…") { window?.changeDates() }
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .disabled(!(window?.availability.tripCommands ?? false))
            Button("Export…") { window?.exportCurrentTrip() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(!(window?.availability.tripCommands ?? false))
            Button("Send to iPhone…") { window?.sendCurrentTripToIPhone() }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .disabled(!(window?.availability.tripCommands ?? false))
        }
    }
}

/// View ▸ Map Style and Show Daylight, bound to the shared preferences.
private struct MapStyleMenu: View {
    let preferences: Preferences

    var body: some View {
        @Bindable var preferences = preferences
        Menu("Map Style") {
            Picker("Map Style", selection: $preferences.mapStyle) {
                ForEach(SettingsModel.mapStyles, id: \.id) { Text($0.title).tag($0.id) }
            }
            .pickerStyle(.inline)
            Toggle("Show Daylight", isOn: $preferences.showDaylight)
        }
    }
}
