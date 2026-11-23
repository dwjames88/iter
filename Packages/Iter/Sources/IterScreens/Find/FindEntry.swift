import SwiftUI
import IterFeatures
import IterModel
import IterUI

/// The Find detail, laid out like Apple Maps on the Mac: a full-bleed map and one floating card on the leading edge that holds,
/// as the state demands, the results list (with progress and the per-source list while a search runs), the typed lookup, or
/// the place card. The search field itself lives at the top of the sidebar: the shell places `FindSearchField(model:)` there.
///
/// Reads `AppNavigator` from the environment for sheets, navigation and the Find requests (focus, Search Here, Add Spot).
public struct FindScreen: View {
    let model: FindModel
    let makeConditions: (@MainActor (Place) -> ConditionsModel)?

    public init(model: FindModel) {
        self.model = model
        self.makeConditions = nil
    }

    /// `makeConditions` builds the Conditions model for the place on the card (the shell passes `container.makeConditionsModel`).
    public init(model: FindModel, makeConditions: @escaping @MainActor (Place) -> ConditionsModel) {
        self.model = model
        self.makeConditions = makeConditions
    }

    public var body: some View {
        FindScreenBody(model: model, makeConditions: makeConditions)
    }
}

private struct FindScreenBody: View {
    @Bindable var model: FindModel
    let makeConditions: (@MainActor (Place) -> ConditionsModel)?
    @Environment(AppNavigator.self) private var navigator: AppNavigator?
    @State private var visibleRegion: GeoRegion?
    @State private var dismissed = false
    @State private var conditions: ConditionsModel?

    private var mode: FindCardMode { FindCardMode.of(model) }
    private var showsCard: Bool { mode != .hidden && !(dismissed && mode != .place) }
    private var showsSearchHere: Bool {
        FindSearchHereRule.shows(phase: model.phase, searched: model.area?.region, visible: visibleRegion)
    }

    var body: some View {
        FindCardLayout(showsCard: showsCard) { insets in
            FindMapView(model: model, visibleRegion: $visibleRegion, insets: insets)
                .overlay(alignment: .center) {
                    if mode == .hidden, model.phase == .idle, !model.spots.isAdding, model.spots.adjusting == nil { FindEmptyHint() }
                }
                .overlay(alignment: .top) {
                    if !showsCard, showsSearchHere, model.spots.adjusting == nil, !model.spots.isAdding {
                        FindSearchHereButton { model.searchHere() }.padding(.top, IterSpace.md)
                    }
                }
        } card: {
            FindCardContent(model: model, conditions: conditions, showsSearchHere: showsSearchHere, onClose: { dismissed = true })
        }
        .onChange(of: model.phase) { dismissed = false }
        .onChange(of: model.text) { dismissed = false }
        .onChange(of: navigator?.searchHereRequest ?? 0) { model.searchHere() }
        .onChange(of: navigator?.addSpotRequest ?? 0) { model.spots.beginAdding() }
        .task(id: model.card?.place.id) { await refreshConditions() }
        .onDisappear { conditions?.stop() }
    }

    private func refreshConditions() async {
        conditions?.stop()
        conditions = nil
        guard let make = makeConditions, let place = model.card?.place else { return }
        // Not started here: the summary on the card starts it when it appears and stops it when it goes away.
        conditions = make(place)
    }
}

/// The Find search field for the top of the Mac sidebar: a 37 pt glass capsule, Return runs the search (a lookup, or discovery for
/// "<feature> in <area>"), and ⌘F (`AppNavigator.focusSearch`) focuses it.
public struct FindSearchField: View {
    @Bindable var model: FindModel
    @Environment(AppNavigator.self) private var navigator: AppNavigator?

    public init(model: FindModel) { self.model = model }

    public var body: some View {
        SidebarSearchField(text: $model.text, prompt: "Search places or ask Iter", focusRequest: navigator?.searchFocusRequest ?? 0) {
            model.submit()
        }
    }
}
