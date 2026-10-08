import SwiftUI
import IterCore
import IterFeatures

/// iPhone (and compact-width iPad), laid out as Find My: the map fills the screen and one system sheet floats over it,
/// holding the tab bar (Explore, Trips, Locations, Settings and search) at its foot. A sheet over a tab bar would cover
/// it; with the tabs inside the sheet, the sheet is the app. At its smaller heights it is Liquid Glass and the map
/// stays interactive behind it.
/// Each tab keeps its own stack; the stacks are views onto `AppNavigation`, so a shared view's
/// `navigation.show(.trip(id))` or `navigation.open(route)` lands on the right tab.
struct PhoneShell: View {
    @Environment(AppModel.self) private var model
    @Environment(ExploreModel.self) private var explore
    @Environment(AppNavigation.self) private var navigation
    @Environment(ShellState.self) private var shell
    @State private var detent = PhoneSheet.launchDetent
    @State private var sheetHeight: CGFloat = 0
    @State private var backdrop = PhoneBackdrop()

    var body: some View {
        map
            .sheet(isPresented: sheetPresented) {
                tabs
                    .environment(\.isInFloatingSheet, true)
                    .environment(\.isOnGlass, true)
                    .environment(backdrop)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { sheetHeight = $0 }
                    .presentationDetents([PhoneSheet.peek, .medium, .large], selection: $detent)
                    .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                    .presentationDragIndicator(.visible)
                    .interactiveDismissDisabled()
            }
            .onAppear { explore.requestInitialCamera() }
            .onChange(of: explore.showsPanel) { _, shows in
                if shows, detent == PhoneSheet.peek { detent = .medium }
            }
    }

    /// The one map behind the sheet; like Find My's, it shows the current tab's content.
    @ViewBuilder private var map: some View {
        let inset = min(sheetHeight, PhoneSheet.mapInsetLimit)
        if shell.phoneTab == .trips, let trip = backdrop.trip {
            @Bindable var backdrop = backdrop
            TripRouteMapView(builder: trip, selectedDay: $backdrop.tripDay, onSelectStop: { backdrop.onSelectStop($0) },
                             backdropInset: inset)
                .id(ObjectIdentifier(trip))
                .ignoresSafeArea(edges: .bottom)
        } else if shell.phoneTab == .locations {
            LocationsMapHeader(items: backdrop.locations, onOpen: { navigation.open(SpotRoute(spot: $0)) }, backdropInset: inset)
                .ignoresSafeArea(edges: .bottom)
        } else {
            ExploreMapLayer(explore: explore, bottomInset: inset,
                            onPinSelected: { if detent == PhoneSheet.peek { detent = .medium } })
        }
    }

    /// Always up, except while the first-run guide (a sheet from the scene root) is showing.
    private var sheetPresented: Binding<Bool> {
        Binding(get: { !model.onboarding.isPresented }, set: { _ in })
    }

    private var tabs: some View {
        @Bindable var shell = shell
        @Bindable var navigation = navigation
        return TabView(selection: tabBinding) {
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

/// The phone sheet's heights: a peek (the title and the tab bar), half and full, as in Find My.
enum PhoneSheet {
    static let peek = PresentationDetent.height(200)
    /// The map's bottom inset stops growing at half height, so framing does not jump when the sheet goes full.
    static var mapInsetLimit: CGFloat { 460 }
    static var launchDetent: PresentationDetent {
        switch AppLaunch.sheetDetent {
        case .peek: peek
        case .full: .large
        case .half, nil: .medium
        }
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
