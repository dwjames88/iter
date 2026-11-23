import SwiftUI
import IterFeatures
import IterModel
import IterScreens
import IterUI

/// iPad (regular width): a sidebar split view like the Mac's. The sidebar selection drives `navigator.route`; Go and
/// Settings are rows of their own.
struct PadShell: View {
    let shell: IOSShell

    var body: some View {
        @Bindable var shell = shell
        NavigationSplitView {
            PadSidebar(shell: shell)
        } detail: {
            switch shell.padSelection {
            case .app(let route): PadDetail(shell: shell, route: route)
            case .go: GoPadDetail(shell: shell)
            case .settings: NavigationStack { IOSSettingsScreen(shell: shell) }
            }
        }
        .environment(\.isOnGlass, false)
        .shellPresentations(shell)
    }
}

struct PadSidebar: View {
    let shell: IOSShell
    private var library: LibraryModel { shell.library }

    var body: some View {
        List(selection: Binding(get: { Optional(shell.padSelection) }, set: { if let value = $0 { shell.padSelection = value } })) {
            Section {
                Label("Find", systemImage: "binoculars").tag(IOSShell.PadSelection.app(.find))
            }
            Section("Trips") {
                Label("All Trips", systemImage: "map").tag(IOSShell.PadSelection.app(.allTrips))
                ForEach(library.pinnedTripFolders) { folder in
                    Label(folder.name, systemImage: "folder").tag(IOSShell.PadSelection.app(.tripFolder(folder.id)))
                }
                ForEach(library.pinnedTrips) { trip in
                    Label(trip.name, systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                        .tag(IOSShell.PadSelection.app(.trip(trip.id)))
                }
            }
            Section("Saved Places") {
                Label("Saved Places", systemImage: "mappin.and.ellipse").tag(IOSShell.PadSelection.app(.savedPlaces))
                ForEach(library.pinnedPlaceFolders) { folder in
                    Label(folder.name, systemImage: "folder").tag(IOSShell.PadSelection.app(.placeFolder(folder.id)))
                }
                ForEach(library.pinnedPlaces) { place in
                    Label(place.name, systemImage: LightText.symbol(place.category)).tag(IOSShell.PadSelection.app(.place(place.id)))
                }
            }
            Section {
                Label("Go", systemImage: "location.north.line").tag(IOSShell.PadSelection.go)
                    .badge(shell.go.isRunning ? Text("Trip Running") : nil)
                Label("Settings", systemImage: "gearshape").tag(IOSShell.PadSelection.settings)
            }
        }
        .navigationTitle("Iter")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("New Trip", systemImage: "plus") { shell.navigator.present(.newTrip(templateID: nil, firstPlace: nil)) }
                    Button("Add Spot on Map", systemImage: "mappin") { shell.navigator.addSpot() }
                } label: { Label("New Trip or Place", systemImage: "plus") }
            }
        }
    }
}
