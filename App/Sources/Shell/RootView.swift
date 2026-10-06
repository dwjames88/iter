import SwiftUI
import IterCore
import IterDesign
import IterData
import IterFeatures

/// The main window: sidebar and detail (plan 6.1-A, pattern #14).
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    @Environment(\.openSettings) private var openSettings
    @State private var navigation = AppNavigation()
    @SceneStorage("sidebarSelection") private var storedSelection: Data?

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: IterSize.sidebarMin, ideal: IterSize.sidebarIdeal, max: IterSize.sidebarMax)
        } detail: {
            DetailView()
        }
        .environment(navigation)
        .frame(minWidth: IterSize.mainWindowMinWidth, minHeight: IterSize.windowMinHeight)
        .focusedSceneValue(\.navigation, navigation)
        .appliesStoredPreferences()
        .onAppear {
            model.store.undoManager = undoManager
            restoreSelection()
        }
        .task { if AppLaunch.settingsTab != nil { openSettings() } }
        .onChange(of: undoManager) { _, new in model.store.undoManager = new }
        // A .iter file opened from Finder (or dropped on the Dock icon) lands here as a new trip.
        .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
        .onOpenURL { url in importTrip(from: url) }
        .alert(String(localized: "Couldn't open this trip", comment: "Alert title"), isPresented: $showsImportError) {
            Button(String(localized: "OK", comment: "Alert button")) {}
        } message: {
            Text(importError)
        }
        .onChange(of: navigation.selection) { _, new in
            storedSelection = try? JSONEncoder().encode(new)
        }
    }

    @State private var showsImportError = false
    @State private var importError = ""

    private func importTrip(from url: URL) {
        guard url.isFileURL else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let document = try TripDocument.decode(Data(contentsOf: url))
            let trip = model.store.importTrip(document)
            navigation.show(.trip(trip.id))
        } catch TripDocument.DocumentError.unsupportedVersion {
            importError = String(localized: "It was made by a newer version of Iter.", comment: "Import error")
            showsImportError = true
        } catch {
            importError = String(localized: "The file isn't a readable Iter trip.", comment: "Import error")
            showsImportError = true
        }
    }

    private func restoreSelection() {
        defer {
            if let forced = AppLaunch.section {
                navigation.selection = forced
            } else if AppLaunch.sectionName == "trip", let first = model.store.trips().first {
                navigation.selection = .trip(first.id)
            }
            if let spot = AppLaunch.spot {
                navigation.selection = .explore
                navigation.explorePath = [SpotRoute(spot: spot)]
            }
        }
        guard let data = storedSelection, let item = try? JSONDecoder().decode(SidebarItem?.self, from: data) else { return }
        if case .trip(let id) = item, model.store.trip(id: id) == nil {
            navigation.selection = .trips
        } else {
            navigation.selection = item
        }
    }
}

/// The detail column for the current sidebar selection.
struct DetailView: View {
    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        @Bindable var navigation = navigation
        switch navigation.selection {
        case .trips, nil:
            NavigationStack(path: $navigation.tripPath) {
                TripsHomeView().spotDestination()
            }
        case .trip(let id):
            NavigationStack(path: $navigation.tripPath) {
                TripBuilderView(tripID: id).spotDestination()
            }
            .id(id)
        case .explore:
            NavigationStack(path: $navigation.explorePath) {
                ExploreView().spotDestination()
            }
        case .saved:
            NavigationStack(path: $navigation.savedPath) {
                SavedView().spotDestination()
            }
        case .scout:
            NavigationStack(path: $navigation.scoutPath) {
                ScoutView().spotDestination()
            }
        }
    }
}

extension View {
    /// Every section can push a spot page.
    func spotDestination() -> some View {
        navigationDestination(for: SpotRoute.self) { route in
            SpotDetailView(spot: route.spot, initialDay: route.day)
        }
    }
}

extension FocusedValues {
    @Entry var navigation: AppNavigation?
}
