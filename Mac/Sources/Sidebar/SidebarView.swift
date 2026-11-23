import SwiftUI
import IterFeatures
import IterModel
import IterUI

/// The system sidebar: a `List(selection:)` in the sidebar style whose rows are IterUI's sidebar parts. The glass search
/// field sits in a top inset and the info and + buttons in a bottom inset, as in Apple Maps.
struct SidebarView: View {
    let window: WindowShell

    private var library: LibraryModel { window.library }

    var body: some View {
        @Bindable var navigator = window.navigator
        List(selection: $navigator.route) {
            Section {
                SidebarRow("Find", systemImage: "binoculars").tag(AppRoute.find)
            } header: { SidebarSectionHeader("Find") }

            Section {
                SidebarDisclosureRow("All Trips", systemImage: "map", tag: AppRoute.allTrips, storageKey: "iter.sidebar.allTrips",
                                     hasChildren: !library.pinnedTripFolders.isEmpty || !library.pinnedTrips.isEmpty) {
                    ForEach(library.pinnedTripFolders) { folder in
                        folderRow(folder, route: .tripFolder(folder.id)) { library.setFolderPinned(folder.id, false) }
                    }
                    ForEach(library.pinnedTrips) { trip in tripRow(trip) }
                }
            } header: { SidebarSectionHeader("Trips") }

            Section {
                SidebarDisclosureRow("Saved Places", systemImage: "mappin.and.ellipse", tag: AppRoute.savedPlaces,
                                     storageKey: "iter.sidebar.savedPlaces",
                                     hasChildren: !library.pinnedPlaceFolders.isEmpty || !library.pinnedPlaces.isEmpty) {
                    ForEach(library.pinnedPlaceFolders) { folder in
                        folderRow(folder, route: .placeFolder(folder.id)) { library.setFolderPinned(folder.id, false) }
                    }
                    ForEach(library.pinnedPlaces) { place in placeRow(place) }
                }
            } header: { SidebarSectionHeader("Saved Places") }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top, spacing: 0) {
            SidebarFindFieldPlaceholder(window: window)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SidebarFooter(window: window)
        }
    }

    // MARK: Rows

    private func tripRow(_ trip: TripRow) -> some View {
        SidebarRow(trip.name, systemImage: "point.topleft.down.to.point.bottomright.curvepath") {
            if trip.isPinned { PackBadge(trip: trip, container: window.container) }
        }
        .tag(AppRoute.trip(trip.id))
        .contextMenu {
            Button("Open") { window.navigator.open(.trip(trip.id)) }
            Button("Unpin Trip") { library.setTripPinned(trip.id, false) }
            Divider()
            Button("Delete Trip", role: .destructive) { library.deleteTrip(trip.id) }
        }
    }

    private func folderRow(_ folder: FolderRow, route: AppRoute, unpin: @escaping () -> Void) -> some View {
        SidebarRow(folder.name, systemImage: "folder")
            .tag(route)
            .contextMenu {
                Button("Open") { window.navigator.open(route) }
                Button("Unpin from Sidebar", action: unpin)
            }
    }

    private func placeRow(_ place: PlaceRow) -> some View {
        SidebarRow(place.name, systemImage: LightText.symbol(place.category))
            .tag(AppRoute.place(place.id))
            .contextMenu {
                Button("Open") { window.navigator.open(.place(place.id)) }
                Button("Unpin from Sidebar") { library.setPlacePinned(place.id, false) }
            }
    }
}

/// The sidebar's search field. PLACEHOLDER: the Find worker's `FindSearchField(model:)` replaces this one view; until it
/// lands this is IterUI's `SidebarSearchField` bound to the Find model's text, Return running the search.
struct SidebarFindFieldPlaceholder: View {
    let window: WindowShell

    var body: some View {
        @Bindable var find = window.find
        SidebarSearchField(text: $find.text, prompt: "Find Spots", focusRequest: window.navigator.searchFocusRequest) {
            window.navigator.open(.find)
            window.find.submit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

/// The foot of the sidebar: the Sample Data banner (sample mode only), the score legend and the + menu.
struct SidebarFooter: View {
    let window: WindowShell

    var body: some View {
        SidebarBottomBar(infoLabel: "What the Scores Mean", addLabel: "New Trip or Place") {
            ScoreLegendView()
                .padding(IterSpace.lg)
                .frame(width: 340, height: 560)
        } addItems: {
            Button("New Trip") { window.newTrip() }
            Button("Add Spot on Map") { window.addSpot() }
        } banner: {
            if window.container.dataMode == .sample { SampleDataBanner() }
        }
    }
}

/// An offline pack glyph on a pinned trip: ready once a pack has been built, a download arrow until then.
struct PackBadge: View {
    let trip: TripRow
    let container: AppContainer
    @State private var builtAt: Date?

    var body: some View {
        Image(systemName: builtAt == nil ? "arrow.down.circle" : "checkmark.circle")
            .foregroundStyle(.secondary)
            .help(builtAt == nil ? "Preparing for offline use" : "Ready offline")
            .accessibilityLabel(builtAt == nil ? "Preparing for offline use" : "Ready offline")
            .task(id: trip.updatedAt) { builtAt = await container.conditionsService.packBuiltAt(tripID: trip.id) }
    }
}

/// The Sample Data banner. Its height is fixed: a banner whose height depends on the sidebar's width made AppKit's layout
/// pass never settle with the trip inspector open (a crash in the old shell).
struct SampleDataBanner: View {
    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 0) {
                Text("Sample Data").font(IterFont.captionStrong)
                Text("Scores use made-up weather. Quit and open Iter without the sample switch to turn it off.")
                    .font(IterFont.caption)
                    .foregroundStyle(IterColor.textSecondary)
                    .lineLimit(3)
            }
        } icon: {
            Image(systemName: "flask").foregroundStyle(IterColor.warning)
        }
        .padding(IterSpace.sm)
        .frame(maxWidth: .infinity, minHeight: 64, maxHeight: 64, alignment: .leading)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: IterRadius.control, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
