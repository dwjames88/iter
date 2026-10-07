import SwiftUI
import IterCore
import IterData
import IterDesign
import IterFeatures

/// Explore (plan 6.2-B on the Mac): a fixed, resizable list column beside a full-height map.
///
/// Why a split view and not a floating panel: the list is the screen's main reading surface (45 rows, each
/// with its light), so it deserves a column of its own that never hides pins or fights the map's controls.
/// `HSplitView` gives the native draggable divider, remembers nothing it should not, and keeps the map's visible
/// region honest: whatever the camera reports is what the user sees, so "pan the selection into view" needs no
/// panel-inset arithmetic. The place card is the only thing that floats over the map.
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
    static var ask: [ObjectIdentifier: Int] = [:]
}

private struct ExploreContent: View {
    @Bindable var explore: ExploreModel
    @Environment(AppModel.self) private var model
    @Environment(AppNavigation.self) private var navigation
    @FocusState private var searchFocused: Bool
    @Environment(\.openURL) private var openURL

    var body: some View {
        ResizableSplit(storageKey: "explore", idealWidth: IterSize.listIdeal) {
            ExploreListPanel(explore: explore)
        } trailing: {
            ExploreMapPane(explore: explore)
        }
        .navigationTitle(Text("Explore", comment: "Window title"))
        .searchable(text: $explore.query, placement: .toolbar,
                    prompt: explore.askMode ? Text(LightText.askPrompt) : Text("Search", comment: "Explore search field prompt"))
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
        .onChange(of: navigation.askRequest) { handleRequests() }
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
        if navigation.askRequest != HandledRequests.ask[key, default: 0] {
            HandledRequests.ask[key] = navigation.askRequest
            explore.askMode = true
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
        ToolbarItem(placement: .primaryAction) {
            Toggle(isOn: $explore.askMode) {
                Label(LightText.askToggleLabel, systemImage: "sparkles")
            }
            .toggleStyle(.button)
            .help(LightText.askToggleHelp)
            .accessibilityLabel(LightText.askToggleLabel)
            .accessibilityValue(explore.askMode ? LightText.askOn : LightText.askOff)
        }
    }
}
