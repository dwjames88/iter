import SwiftUI
import IterFeatures
import IterModel
import IterUI

/// The Find map for the iPhone: the map the Mac's Find screen draws (pins, clusters, your own spots, the area's outline, Add Spot,
/// Adjust Location) with everything inset above the sheet, and Search Here as a glass capsule at the top when the map no longer
/// matches the list. Reads `AppNavigator` (Search Here and Add Spot requests) and `\.findMapStyle` from the environment.
public struct FindPhoneMap: View {
    @Bindable var model: FindModel
    let bottomInset: CGFloat
    @State private var visibleRegion: GeoRegion?
    @Environment(AppNavigator.self) private var navigator: AppNavigator?

    public init(model: FindModel, bottomInset: CGFloat) {
        self.model = model
        self.bottomInset = bottomInset
    }

    private var showsSearchHere: Bool {
        FindSearchHereRule.shows(phase: model.phase, searched: model.area?.region, visible: visibleRegion)
            && model.spots.adjusting == nil && !model.spots.isAdding
    }

    public var body: some View {
        FindMapView(model: model, visibleRegion: $visibleRegion,
                    insets: EdgeInsets(top: 0, leading: 0, bottom: bottomInset, trailing: 0))
            .overlay(alignment: .top) {
                if showsSearchHere { FindSearchHereButton { model.searchHere() }.padding(.top, IterSpace.md) }
            }
            .onChange(of: navigator?.searchHereRequest ?? 0) { model.searchHere() }
            .onChange(of: navigator?.addSpotRequest ?? 0) { model.spots.beginAdding() }
    }
}

/// What the Find tab's sheet holds under its search field: the typed lookup, the results with progress and the per-source list
/// while AI discovery runs, or the place card; before anything is searched, a few things to try. The place's Conditions model
/// is built from `makeConditions` for the card and stopped when the card goes. Reads `AppNavigator` from the environment.
public struct FindSheetContent: View {
    @Bindable var model: FindModel
    let makeConditions: (@MainActor (Place) -> ConditionsModel)?
    var showsSources = false
    @State private var conditions: ConditionsModel?

    public init(model: FindModel, makeConditions: (@MainActor (Place) -> ConditionsModel)? = nil, showsSources: Bool = false) {
        self.model = model
        self.makeConditions = makeConditions
        self.showsSources = showsSources
    }

    public var body: some View {
        Group {
            if FindCardMode.of(model) == .hidden {
                FindSheetIdle(model: model)
            } else {
                // The Search Here capsule floats over the map; the card does not repeat it.
                FindCardContent(model: model, conditions: conditions, showsSearchHere: false, initiallyShowsSources: showsSources)
            }
        }
        .task(id: model.card?.place.id) { refreshConditions() }
        .onDisappear { conditions?.stop() }
    }

    private func refreshConditions() {
        conditions?.stop()
        conditions = nil
        guard let make = makeConditions, let place = model.card?.place else { return }
        // Not started here: the summary on the card starts it when it appears and stops it when it goes away.
        conditions = make(place)
    }
}

/// Before anything is searched: how to ask, and a few searches to try.
struct FindSheetIdle: View {
    @Bindable var model: FindModel

    static let examples = ["Waterfalls in Yosemite", "Sunrise viewpoints in Acadia", "Dark sky spots near Moab"]

    var body: some View {
        List {
            Section {
                ForEach(Self.examples, id: \.self) { example in
                    Button {
                        model.text = example
                        model.askIter()
                    } label: {
                        Label { Text(verbatim: example).foregroundStyle(IterColor.textPrimary) }
                            icon: { Image(systemName: "sparkles").foregroundStyle(IterColor.accentText) }
                            .frame(minHeight: 44, alignment: .leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Rectangle().fill(ContentFill()))
                }
            } header: {
                Text("Search for a place, or ask for spots", comment: "Find idle header")
            }
            Section {
                Button { model.spots.beginAdding() } label: {
                    Label { Text("Add Spot", comment: "Button").foregroundStyle(IterColor.textPrimary) }
                        icon: { Image(systemName: "mappin.and.ellipse").foregroundStyle(IterColor.accentText) }
                        .frame(minHeight: 44, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(Rectangle().fill(ContentFill()))
            } footer: {
                Text("Drop a pin for a spot of your own, then touch and hold the pin to move it.", comment: "Find idle footer")
            }
        }
        .phoneGroupedList()
    }
}

extension EnvironmentValues {
    /// Set on the iPhone: "Add Stop" in the Trip Builder calls this with the day (zero-based) instead of opening the saved-places
    /// popover, so the app can take the user to the Find tab with the trip as the add target. nil on the Mac and iPad.
    @Entry public var tripBuilderAddStopFromFind: (@MainActor (_ tripID: UUID, _ day: Int) -> Void)? = nil
}
