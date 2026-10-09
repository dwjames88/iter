import SwiftUI
import IterCore
import IterData
import IterDesign
import IterFeatures

/// The sidebar: Trips and Locations (each: its "All" page, then what is pinned) and Find. A system source list; the
/// sections are in their own files. Folders are managed inside All Trips and All Locations, not here.
struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppNavigation.self) private var navigation
    @State private var showsLegend = false

    var body: some View {
        @Bindable var navigation = navigation
        List(selection: $navigation.selection) {
            SidebarTripsSection()
            SidebarLocationsSection()
            Section {
                Label(String(localized: "Explore", comment: "Sidebar item"), systemImage: "binoculars")
                    .tag(SidebarItem.explore)
            } header: {
                Text("Find", comment: "Sidebar section")
            }
        }
        .listStyle(.sidebar)
        .snapshotOpaqueBackground()
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: IterSpace.sm) {
                if model.sampleDataEnabled { SampleDataLabel(style: .banner) }
                HStack {
                    legendButton
                    Spacer()
                }
            }
            .padding(IterSpace.sm)
        }
        .toolbar {
            ToolbarItem {
                addMenu
            }
        }
    }

    /// The "i" at the bottom of the sidebar: what the scores and colours mean, in a popover.
    private var legendButton: some View {
        Button { showsLegend.toggle() } label: {
            Image(systemName: "info.circle").font(.system(size: IterSize.iconSmall))
        }
        .buttonStyle(.borderless)
        .foregroundStyle(IterColor.textSecondary)
        .help(Text("What the scores mean", comment: "Tooltip"))
        .accessibilityLabel(Text("What the scores mean", comment: "Button"))
        .popover(isPresented: $showsLegend, arrowEdge: .trailing) {
            ScoreLegendPopover(source: model.weather.settings.primary)
        }
    }

    private var addMenu: some View {
        Menu {
            Button(String(localized: "New Trip", comment: "Menu item")) {
                navigation.newTripRequest += 1
                if case .trip = navigation.selection {} else { navigation.selection = .trips }
            }
            Button(String(localized: "New Location", comment: "Menu item: drops a pin on the Explore map")) {
                navigation.show(.explore)
                navigation.addSpotModeRequest += 1
            }
        } label: {
            Label(String(localized: "New", comment: "Toolbar button"), systemImage: "plus")
        }
        .menuIndicator(.hidden)
        .help(Text("New Trip or Location", comment: "Tooltip"))
    }
}
