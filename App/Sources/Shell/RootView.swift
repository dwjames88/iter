import SwiftUI
import IterCore
import IterDesign
import IterFeatures

/// The main window: sidebar and detail (plan 6.1-A, pattern #14).
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
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
        .onChange(of: undoManager) { _, new in model.store.undoManager = new }
        .onChange(of: navigation.selection) { _, new in
            storedSelection = try? JSONEncoder().encode(new)
        }
    }

    private func restoreSelection() {
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
