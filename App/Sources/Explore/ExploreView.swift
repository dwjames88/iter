import SwiftUI
import IterCore
import IterData
import IterDesign
import IterFeatures

/// Explore on the Mac, laid out like Apple Maps: the map fills the window and the list floats over its leading edge on
/// a Liquid Glass panel (`FloatingPanelLayout`). The map's leading safe area clears the panel, so framing and "pan the
/// selection into view" stay in the visible part. A selected place opens in the panel, as a place card does in Maps.
struct ExploreView: View {
    @Environment(AppModel.self) private var model
    @State private var explore: ExploreModel?
    /// Test and snapshot hook: puts the screen in a given state right after it is built.
    var configure: (@MainActor (ExploreModel) -> Void)?

    var body: some View {
        if let explore {
            ExploreContent(explore: explore)
        } else {
            Color.clear.onAppear {
                let made = ExploreModel(app: model)
                configure?(made)
                if let add = AppLaunch.addSpot {
                    // The spot editor's Save, without the sheet: default zone from the coordinate, then fetch.
                    let draft = SpotDraft(coordinate: add.coordinate)
                    let record = model.store.createUserSpot(name: add.name, coordinate: draft.coordinate,
                                                            timeZoneIdentifier: draft.timeZoneIdentifier)
                    model.spotSaved(record.spot)
                    made.didCreate(record.spot)
                    made.requestScroll(to: record.spot.id)
                }
                if let text = AppLaunch.searchText {
                    made.query = text
                    made.searchAppleMaps()
                }
                if let text = AppLaunch.askText {
                    made.query = text
                    made.ask()
                }
                if let id = AppLaunch.selectRowID, made.row(id: id) != nil {
                    made.select(id, from: .list)
                    made.openPanel()
                    made.requestScroll(to: id)
                }
                explore = made
                if ExplorePerfScript.enabled { Task { await ExplorePerfScript.run(made) } }
            }
        }
    }
}

/// Requests from menus that were already handled by a previous Explore view, per window.
@MainActor private enum HandledRequests {
    static var focus: [ObjectIdentifier: Int] = [:]
    static var addSpot: [ObjectIdentifier: Int] = [:]
}

private struct ExploreContent: View {
    @Bindable var explore: ExploreModel
    @Environment(AppModel.self) private var model
    @Environment(AppNavigation.self) private var navigation
    @FocusState private var searchFocused: Bool
    @Environment(\.openURL) private var openURL

    var body: some View {
        FloatingPanelLayout {
            ExploreListPanel(explore: explore)
        } map: { insets in
            ExploreMapPane(explore: explore, insets: insets)
        }
        .navigationTitle(Text("Explore", comment: "Window title"))
        .toolbar(removing: .title)
        .searchable(text: $explore.query, placement: .sidebar,
                    prompt: Text("Search places or ask Iter", comment: "Explore search field prompt: one field for place names and requests"))
        .searchFocused($searchFocused)
        .onSubmit(of: .search) { explore.submitSearch() }
        .toolbar { toolbar }
        .sheet(isPresented: draftPresented) {
            if let coordinate = explore.draftCoordinate {
                SpotEditorSheet(mode: .create(coordinate)) { record in explore.didCreate(record.spot) }
            }
        }
        .task(id: explore.rows.map(\.id)) { explore.requestForecasts() }
        .onAppear {
            explore.start()
            explore.requestInitialCamera()
            handleRequests()
        }
        // A fix that arrives later, or a new radius, regroups the list; the camera follows unless the user moved it.
        .onChange(of: model.location.coordinate) { explore.locationChanged() }
        .onChange(of: model.location.radiusMiles) { explore.contentChanged() }
        .onChange(of: navigation.focusSearchRequest) { handleRequests() }
        .onChange(of: navigation.addSpotModeRequest) { handleRequests() }
    }

    private var draftPresented: Binding<Bool> {
        Binding(get: { explore.draftCoordinate != nil }, set: { if !$0 { explore.cancelDraft() } })
    }

    private func handleRequests() {
        let key = ObjectIdentifier(navigation)
        if navigation.focusSearchRequest != HandledRequests.focus[key, default: 0] {
            HandledRequests.focus[key] = navigation.focusSearchRequest
            searchFocused = true
        }
        if navigation.addSpotModeRequest != HandledRequests.addSpot[key, default: 0] {
            HandledRequests.addSpot[key] = navigation.addSpotModeRequest
            explore.beginAddingSpot()
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                if let region = explore.visibleRegion {
                    openURL(WindyLink.url(center: region.center, zoom: WindyLink.zoom(forLatitudeDelta: region.latitudeDelta)))
                }
            } label: {
                Label(String(localized: "Windy", comment: "Toolbar button: open the map area on windy.com"), systemImage: "wind")
            }
            .disabled(explore.visibleRegion == nil)
            .help(String(localized: "Open this map area on windy.com", comment: "Tooltip"))
        }
        ToolbarItem(placement: .primaryAction) {
            Toggle(isOn: $explore.isAddingSpot) {
                Label(String(localized: "Add Spot", comment: "Toolbar toggle: click the map to add your own spot"),
                      systemImage: "mappin.and.ellipse")
            }
            .toggleStyle(.button)
            .help(String(localized: "Add your own spot: click the map to drop a pin (Esc to cancel)", comment: "Tooltip"))
        }
    }
}
