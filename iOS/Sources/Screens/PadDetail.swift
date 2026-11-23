import SwiftUI
import IterFeatures
import IterModel
import IterScreens
import IterUI

// OWNER: W3 (screens). The iPad detail column for an app route: the Mac's composition (the sidebar is the shell's).

struct PadDetail: View {
    let shell: IOSShell
    let route: AppRoute

    var body: some View {
        Group {
            switch route {
            case .find: PadFindDetail(shell: shell)
            case .allTrips:
                AllTripsScreen(library: shell.library, folderID: nil).environment(\.libraryLightScore, shell.lightScore)
            case .tripFolder(let id):
                AllTripsScreen(library: shell.library, folderID: id).environment(\.libraryLightScore, shell.lightScore).id(id)
            case .trip(let id): PadTripDetail(shell: shell, tripID: id).id(id)
            case .savedPlaces:
                SavedPlacesScreen(library: shell.library, folderID: nil)
            case .placeFolder(let id):
                SavedPlacesScreen(library: shell.library, folderID: id).id(id)
            case .place(let id): PadPlaceDetail(shell: shell, placeID: id).id(id)
            }
        }
        .iterShellEnvironment(shell)
    }
}

/// Find on iPad: the full-bleed map with the floating card, and the search field in the navigation bar.
private struct PadFindDetail: View {
    let shell: IOSShell

    var body: some View {
        @Bindable var find = shell.find
        FindScreen(model: find, makeConditions: shell.makeConditions)
            .searchable(text: $find.text, prompt: Text("Search places or ask Iter", comment: "Find search field prompt"))
            .onSubmit(of: .search) { find.submit() }
            .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
    }
}

/// A trip on iPad: the route map fills the detail and the Trip Builder is the system inspector, with Start Trip in the toolbar.
private struct PadTripDetail: View {
    let shell: IOSShell
    let tripID: UUID
    @State private var inspectorShown = true

    var body: some View {
        let model = shell.buildModel(for: tripID)
        TripRouteMap(model: model, mapStyle: shell.container.preferences.mapStyle)
            .inspector(isPresented: $inspectorShown) {
                TripBuilderPanel(model: model)
                    .environment(\.tripBuilderOpensModel, true)
                    .inspectorColumnWidth(min: 380, ideal: 440, max: 560)
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        StartTripBar(model: model) { start() }
                    }
            }
            .navigationTitle(shell.library.tripRow(id: tripID)?.name ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    ShareTripButton(tripID: tripID, library: shell.library)
                    Button { shell.navigator.present(.changeDates(tripID: tripID)) } label: { Label("Change Dates", systemImage: "calendar") }
                    Button { inspectorShown.toggle() } label: { Label("Trip Builder", systemImage: "sidebar.trailing") }
                }
            }
    }

    private func start() {
        Task { await shell.go.start(tripID: tripID) }
    }
}

private struct PadPlaceDetail: View {
    let shell: IOSShell
    let placeID: UUID
    var body: some View { PhonePlaceScreen(shell: shell, placeID: placeID) }
}
