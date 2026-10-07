import SwiftUI
import IterCore
import IterFeatures

/// iPhone (and compact-width iPad): the iOS 26 floating tab bar with Explore, Trips, Locations, Settings and the separate
/// search button. Each tab keeps its own stack; the stacks are views onto `AppNavigation`, so a shared view's
/// `navigation.show(.trip(id))` or `navigation.open(route)` lands on the right tab.
struct PhoneShell: View {
    @Environment(AppNavigation.self) private var navigation
    @Environment(ShellState.self) private var shell

    var body: some View {
        @Bindable var shell = shell
        @Bindable var navigation = navigation
        TabView(selection: tabBinding) {
            Tab(String(localized: "Explore", comment: "Tab"), systemImage: "map", value: ShellState.PhoneTab.explore) {
                NavigationStack(path: $navigation.explorePath) {
                    PhoneExploreScreen().iosSpotDestination()
                }
            }
            Tab(String(localized: "Trips", comment: "Tab"), systemImage: "car.side", value: ShellState.PhoneTab.trips) {
                NavigationStack(path: tripsPath) {
                    TripsListScreen().phoneRouteDestinations()
                }
            }
            Tab(String(localized: "Locations", comment: "Tab"), systemImage: "mappin.and.ellipse", value: ShellState.PhoneTab.locations) {
                NavigationStack(path: locationsPath) {
                    LocationsScreen(folderID: nil).phoneRouteDestinations()
                }
            }
            Tab(String(localized: "Settings", comment: "Tab"), systemImage: "gearshape", value: ShellState.PhoneTab.settings) {
                NavigationStack { IOSSettingsScreen() }
            }
            Tab(value: ShellState.PhoneTab.search, role: .search) {
                NavigationStack(path: $navigation.explorePath) {
                    ExploreSearchScreen(onShowPlace: { navigation.show(.explore) }).iosSpotDestination()
                }
            }
        }
        .onAppear { shell.usesTabs = true }
    }

    /// Tapping a tab moves the shared selection there (back to the trip or folder that tab had open).
    private var tabBinding: Binding<ShellState.PhoneTab> {
        Binding(get: { shell.phoneTab }, set: { tab in
            shell.phoneTab = tab
            switch tab {
            case .explore: navigation.selection = .explore
            case .trips: navigation.selection = shell.openTripID.map(SidebarItem.trip) ?? .trips
            case .locations: navigation.selection = shell.openFolderID.map(SidebarItem.locationFolder) ?? .locations
            case .settings, .search: break
            }
        })
    }

    /// Trips stack = [the open trip] + the spot pages pushed from it (`navigation.tripPath`).
    private var tripsPath: Binding<[PhoneRoute]> {
        Binding(get: {
            (shell.openTripID.map { [PhoneRoute.trip($0)] } ?? []) + navigation.tripPath.map(PhoneRoute.spot)
        }, set: { routes in
            var trip: UUID?
            if case .trip(let id) = routes.first { trip = id }
            shell.openTripID = trip
            navigation.tripPath = routes.compactMap { if case .spot(let r) = $0 { r } else { nil } }
            let wanted: SidebarItem = trip.map(SidebarItem.trip) ?? .trips
            if navigation.selection != wanted { navigation.selection = wanted }
        })
    }

    /// Locations stack = [the open folder] + the spot pages pushed from it (`navigation.locationsPath`).
    private var locationsPath: Binding<[PhoneRoute]> {
        Binding(get: {
            (shell.openFolderID.map { [PhoneRoute.folder($0)] } ?? []) + navigation.locationsPath.map(PhoneRoute.spot)
        }, set: { routes in
            var folder: UUID?
            if case .folder(let id) = routes.first { folder = id }
            shell.openFolderID = folder
            navigation.locationsPath = routes.compactMap { if case .spot(let r) = $0 { r } else { nil } }
            let wanted: SidebarItem = folder.map(SidebarItem.locationFolder) ?? .locations
            if navigation.selection != wanted { navigation.selection = wanted }
        })
    }
}

extension View {
    /// Destinations of the phone's Trips and Locations stacks.
    func phoneRouteDestinations() -> some View {
        navigationDestination(for: PhoneRoute.self) { route in
            switch route {
            case .trip(let id): TripBuilderScreen(tripID: id).id(id)
            case .folder(let id): LocationsScreen(folderID: id).id(id)
            case .spot(let spot): SpotPageScreen(route: spot)
            }
        }
    }
}
