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

    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var autoCollapsed = false
    @State private var windowWidth: CGFloat = 0
    /// Below this the sidebar, list and detail cannot all fit at their minimums.
    private var sidebarCollapseWidth: CGFloat { IterSize.sidebarIdeal + IterSize.mainWindowMinWidth }

    /// The sidebar gives way first: collapse it when the WINDOW is too narrow for sidebar plus detail minimum, bring it
    /// back when there is room again, but only if this rule (not the person) collapsed it.
    private func applyCollapseRule(_ width: CGFloat) {
        guard width > 0 else { return }
        if width < sidebarCollapseWidth {
            if columnVisibility != .detailOnly { columnVisibility = .detailOnly; autoCollapsed = true }
        } else if autoCollapsed {
            autoCollapsed = false
            columnVisibility = .all
        }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: IterSize.sidebarMin, ideal: IterSize.sidebarIdeal, max: IterSize.sidebarMax)
        } detail: {
            DetailView()
        }
        .environment(navigation)
        .frame(minWidth: IterSize.mainWindowMinWidth, minHeight: IterSize.windowMinHeight)
        .background(MainWindowConfigurator(minSize: CGSize(width: IterSize.mainWindowMinWidth, height: IterSize.windowMinHeight), contentWidth: $windowWidth))
        .onChange(of: windowWidth) { _, width in applyCollapseRule(width) }
        .onChange(of: columnVisibility) { _, new in
            if new == .all { autoCollapsed = false }
        }
        .focusedSceneValue(\.navigation, navigation)
        .onAppear {
            IterPerf.once("window.appear")
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
        // A selected trip or folder that is deleted (or whose creation is undone) falls back to its section's landing.
        .onChange(of: model.store.revision) { fixStaleSelection() }
    }

    @State private var showsImportError = false
    @State private var importError = ""

    private func importTrip(from url: URL) {
        guard url.isFileURL else { return }
        // False when unsandboxed (or the URL needs no scope): the read below still proceeds.
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

    /// The landing a selection falls back to when the trip or folder it points at no longer exists.
    private func fixStaleSelection() {
        switch navigation.selection {
        case .trip(let id) where model.store.trip(id: id) == nil: navigation.selection = .trips
        case .locationFolder(let id) where model.store.folder(id: id) == nil: navigation.selection = .locations
        default: break
        }
    }

    private func restoreSelection() {
        defer {
            if let forced = AppLaunch.section {
                navigation.selection = forced
            } else if AppLaunch.sectionName == "trip", let first = model.store.pinnedTrips().first ?? model.store.trips().first {
                navigation.selection = .trip(first.id)
            }
            if let name = AppLaunch.locationFolderName,
               let folder = model.store.folders(kind: .locations).flatMap({ [$0] + model.store.subfolders(of: $0) })
                   .first(where: { $0.name == name }) {
                navigation.selection = .locationFolder(folder.id)
            }
            if let spot = AppLaunch.spot {
                navigation.selection = .explore
                navigation.explorePath = [SpotRoute(spot: spot)]
            }
        }
        guard let data = storedSelection, let item = try? JSONDecoder().decode(SidebarItem?.self, from: data) else { return }
        navigation.selection = item
        fixStaleSelection()
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
        case .locations:
            NavigationStack(path: $navigation.locationsPath) {
                LocationsView(folderID: nil).id("all-locations").spotDestination()
            }
        case .locationFolder(let id):
            NavigationStack(path: $navigation.locationsPath) {
                LocationsView(folderID: id).id(id).spotDestination()
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
