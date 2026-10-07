import SwiftUI
import IterCore
import IterData
import IterDesign
import IterFeatures

struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        @Bindable var navigation = navigation
        let trips = tripsSnapshot
        List(selection: $navigation.selection) {
            Section {
                Label(String(localized: "All Trips", comment: "Sidebar item"), systemImage: "map")
                    .tag(SidebarItem.trips)
                ForEach(trips, id: \.id) { trip in
                    Label(trip.name, systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                        .tag(SidebarItem.trip(trip.id))
                        .contextMenu { TripContextMenu(trip: trip) }
                }
            } header: {
                Text("Trips", comment: "Sidebar section")
            }
            Section {
                Label(String(localized: "Explore", comment: "Sidebar item"), systemImage: "binoculars")
                    .tag(SidebarItem.explore)
                Label(String(localized: "Saved", comment: "Sidebar item"), systemImage: "bookmark")
                    .tag(SidebarItem.saved)
                Label(String(localized: "Scout", comment: "Sidebar item: Apple Intelligence scout"), systemImage: "sparkle.magnifyingglass")
                    .tag(SidebarItem.scout)
            } header: {
                Text("Find", comment: "Sidebar section")
            }
        }
        .listStyle(.sidebar)
        .snapshotOpaqueBackground()
        .safeAreaInset(edge: .bottom) {
            if model.sampleDataEnabled {
                SampleDataLabel(style: .banner).padding(IterSpace.sm)
            }
        }
        .toolbar {
            ToolbarItem {
                Button {
                    navigation.newTripRequest += 1
                    if case .trip = navigation.selection {} else { navigation.selection = .trips }
                } label: {
                    Label(String(localized: "New Trip", comment: "Toolbar button"), systemImage: "plus")
                }
                .help(Text("New Trip (⌘N)", comment: "Tooltip"))
            }
        }
    }

    /// Reading `revision` ties the list to store changes.
    private var tripsSnapshot: [TripRecord] {
        _ = model.store.revision
        return model.store.trips()
    }
}

/// Shared context menu for a trip (sidebar and the trips overview).
struct TripContextMenu: View {
    @Environment(AppModel.self) private var model
    @Environment(AppNavigation.self) private var navigation
    let trip: TripRecord

    var body: some View {
        Button(String(localized: "Open", comment: "Context menu")) { navigation.show(.trip(trip.id)) }
        Button(String(localized: "Duplicate", comment: "Context menu")) {
            let copy = model.store.duplicateTrip(trip, name: String(localized: "\(trip.name) copy", comment: "Name of a duplicated trip"))
            navigation.show(.trip(copy.id))
        }
        ShareLink(item: model.store.document(for: trip), preview: SharePreview(trip.name)) {
            Text("Share…", comment: "Context menu")
        }
        Divider()
        Button(String(localized: "Delete Trip", comment: "Context menu"), role: .destructive) {
            if navigation.selection == .trip(trip.id) { navigation.selection = .trips }
            model.store.deleteTrip(trip)
        }
    }
}
