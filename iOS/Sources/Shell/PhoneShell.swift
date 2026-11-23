import SwiftUI
import IterFeatures
import IterScreens
import IterUI

/// iPhone (and a compact-width iPad), laid out as Apple Maps: the current tab's map fills the screen and ONE system sheet
/// floats over it, holding the tab bar at its foot. The sheet is always up (it cannot be dismissed) and keeps the map
/// interactive behind it up to half height.
struct PhoneShell: View {
    let shell: IOSShell

    var body: some View {
        @Bindable var shell = shell
        PhoneMap(shell: shell)
            .sheet(isPresented: Binding(get: { true }, set: { _ in })) {
                PhoneSheetContent(shell: shell)
                    .environment(\.isOnGlass, true)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { shell.sheetHeight = $0 }
                    .presentationDetents(PhoneSheet.detents, selection: $shell.detent)
                    .presentationBackgroundInteraction(.enabled(upThrough: PhoneSheet.half))
                    .presentationDragIndicator(.visible)
                    .interactiveDismissDisabled()
            }
    }
}

/// The one map behind the sheet; like Apple Maps' it shows the current tab's content.
struct PhoneMap: View {
    let shell: IOSShell

    var body: some View {
        Group {
            switch shell.tab {
            case .find: FindTabMap(shell: shell)
            case .trips: TripsTabMap(shell: shell)
            case .saved: SavedTabMap(shell: shell)
            case .go: GoTabMap(shell: shell)
            }
        }
        // The map runs under the status bar, but its controls, framing and Search Here stay below the Dynamic Island: the top
        // safe area is put back as padding (the tab maps themselves do not ignore the safe area).
        .safeAreaPadding(.top, shell.mapTopInset)
        .ignoresSafeArea()
        .background {
            Color.clear.onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { shell.mapTopInset = $0 }
        }
    }
}

/// What is inside the floating sheet: the tabs (the tab bar sits at the sheet's foot) plus the shell's presentations.
struct PhoneSheetContent: View {
    let shell: IOSShell

    var body: some View {
        @Bindable var shell = shell
        TabView(selection: $shell.tab) {
            Tab("Find", systemImage: "magnifyingglass", value: PhoneTab.find) {
                NavigationStack(path: $shell.findPath) {
                    FindTabRoot(shell: shell)
                        .toolbar { SettingsToolbarButton(shell: shell) }
                        .navigationDestination(for: PhoneRoute.self) { PhoneRouteDestination(shell: shell, route: $0) }
                }
            }
            Tab("Trips", systemImage: "car.side", value: PhoneTab.trips) {
                NavigationStack(path: $shell.tripsPath) {
                    TripsTabRoot(shell: shell)
                        .toolbar { SettingsToolbarButton(shell: shell) }
                        .navigationDestination(for: PhoneRoute.self) { PhoneRouteDestination(shell: shell, route: $0) }
                }
            }
            Tab("Saved", systemImage: "mappin.and.ellipse", value: PhoneTab.saved) {
                NavigationStack(path: $shell.savedPath) {
                    SavedTabRoot(shell: shell)
                        .toolbar { SettingsToolbarButton(shell: shell) }
                        .navigationDestination(for: PhoneRoute.self) { PhoneRouteDestination(shell: shell, route: $0) }
                }
            }
            Tab("Go", systemImage: "location.north.line", value: PhoneTab.go) {
                NavigationStack { GoTabRoot(shell: shell) }
            }
        }
        .sheet(isPresented: $shell.showsSettings) { SettingsSheet(shell: shell) }
        .shellPresentations(shell)
    }
}

#if DEBUG
/// D6 probe (`-IterD6Probe YES`, Debug only): the alternative layout, a TabView OUTSIDE with a sheet presented over it, to see
/// whether the system sheet still covers the tab bar. Not a shipping layout.
struct PhoneD6ProbeShell: View {
    let shell: IOSShell

    var body: some View {
        @Bindable var shell = shell
        TabView(selection: $shell.tab) {
            ForEach(PhoneTab.allCases, id: \.self) { tab in
                Tab(tab.rawValue.capitalized, systemImage: "circle", value: tab) { PhoneMap(shell: shell) }
            }
        }
        .sheet(isPresented: Binding(get: { true }, set: { _ in })) {
            NavigationStack {
                switch shell.tab {
                case .find: FindTabRoot(shell: shell)
                case .trips: TripsTabRoot(shell: shell)
                case .saved: SavedTabRoot(shell: shell)
                case .go: GoTabRoot(shell: shell)
                }
            }
            .environment(\.isOnGlass, true)
            .presentationDetents(PhoneSheet.detents, selection: $shell.detent)
            .presentationBackgroundInteraction(.enabled(upThrough: PhoneSheet.half))
            .presentationDragIndicator(.visible)
            .interactiveDismissDisabled()
        }
    }
}
#endif
