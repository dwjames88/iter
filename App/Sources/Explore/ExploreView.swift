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
                explore = made
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

    var body: some View {
        HSplitView {
            ExploreListPanel(explore: explore)
                .frame(minWidth: IterSize.listMin, idealWidth: IterSize.listIdeal, maxWidth: IterSize.listMax)
            ExploreMapPane(explore: explore)
                .frame(minWidth: IterSize.listMin, maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle(Text("Explore", comment: "Window title"))
        .searchable(text: $explore.query, placement: .toolbar,
                    prompt: Text("Search spots and places", comment: "Explore search field prompt"))
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
            explore.requestFit()
            handleRequests()
        }
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
        ToolbarItemGroup(placement: .primaryAction) {
            dateControl
        }
        ToolbarItem(placement: .primaryAction) { intentPicker }
        ToolbarItem(placement: .primaryAction) { filtersMenu }
        ToolbarItem(placement: .primaryAction) { sortMenu }
        ToolbarItem(placement: .primaryAction) {
            Toggle(isOn: $explore.isAddingSpot) {
                Label(String(localized: "Add Spot", comment: "Toolbar toggle: click the map to add your own spot"),
                      systemImage: "mappin.and.ellipse")
            }
            .toggleStyle(.button)
            .help(String(localized: "Add your own spot: click the map to drop a pin (Esc to cancel)", comment: "Tooltip"))
        }
    }

    private static let utc = TimeZone(identifier: "UTC")!

    @ViewBuilder private var dateControl: some View {
        Button {
            explore.shiftDay(by: -1)
        } label: {
            Label(String(localized: "Previous Day", comment: "Toolbar button"), systemImage: "chevron.left")
        }
        .keyboardShortcut("[", modifiers: .command)
        .help(String(localized: "Previous day (⌘[)", comment: "Tooltip"))

        DatePicker(selection: Binding(get: { explore.day.noon(in: Self.utc) },
                                      set: { explore.day = LocalDay($0, in: Self.utc) }),
                   displayedComponents: .date) {
            Text("Date", comment: "Accessibility label of the date picker")
        }
        .labelsHidden()
        .environment(\.timeZone, Self.utc)
        .help(String(localized: "The day whose light is shown", comment: "Tooltip"))

        Button {
            explore.shiftDay(by: 1)
        } label: {
            Label(String(localized: "Next Day", comment: "Toolbar button"), systemImage: "chevron.right")
        }
        .keyboardShortcut("]", modifiers: .command)
        .help(String(localized: "Next day (⌘])", comment: "Tooltip"))

        Button(String(localized: "Today", comment: "Toolbar button: jump to today")) { explore.goToToday() }
            .disabled(explore.isToday)
            .help(String(localized: "Jump to today", comment: "Tooltip"))
    }

    private var intentPicker: some View {
        @Bindable var model = model
        return Picker(selection: $model.preferredIntent) {
            Text(LightText.eachSpotsBest).tag(LightIntent?.none)
            Divider()
            ForEach(LightIntent.allCases) { intent in
                Label(LightText.name(intent), systemImage: LightText.symbol(intent)).tag(LightIntent?.some(intent))
            }
        } label: {
            Label(String(localized: "Light", comment: "Toolbar: which light to look for"), systemImage: "sun.horizon")
        }
        .pickerStyle(.menu)
        .help(String(localized: "Which light to score every spot for", comment: "Tooltip"))
    }

    private var filtersMenu: some View {
        Menu {
            Menu(String(localized: "Category", comment: "Filters submenu")) {
                ForEach(SpotCategory.allCases) { category in
                    Toggle(LightText.name(category), isOn: member(category, of: \.categories))
                }
            }
            Menu(String(localized: "Known For", comment: "Filters submenu: what the spot is best at")) {
                ForEach(BestLight.allCases) { best in
                    Toggle(LightText.name(best), isOn: member(best, of: \.bestLight))
                }
            }
            Menu(String(localized: "Source", comment: "Filters submenu")) {
                ForEach(ExploreSource.allCases) { source in
                    Toggle(LightText.name(source), isOn: member(source, of: \.sources))
                }
            }
            Divider()
            Button(String(localized: "Clear Filters", comment: "Menu item")) { explore.filters = .none }
                .disabled(!explore.filters.isActive)
        } label: {
            let count = explore.filters.activeCount
            HStack(spacing: IterSpace.xs) {
                Image(systemName: count > 0 ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                if count > 0 { Text(count, format: .number).monospacedDigit() }
            }
            .accessibilityLabel(Text("Filters", comment: "Toolbar menu"))
            .accessibilityValue(count > 0 ? Text("\(count) active", comment: "VoiceOver: number of active filters") : Text("None active", comment: "VoiceOver"))
        }
        .help(String(localized: "Filter by category, what a spot is known for, and source", comment: "Tooltip"))
    }

    private var sortMenu: some View {
        Menu {
            Picker(selection: $explore.sort) {
                ForEach(ExploreSort.allCases) { sort in Text(LightText.name(sort)).tag(sort) }
            } label: {
                Text("Sort", comment: "Menu title")
            }
            .pickerStyle(.inline)
        } label: {
            Label(String(localized: "Sort", comment: "Toolbar menu"), systemImage: "arrow.up.arrow.down")
        }
        .help(String(localized: "Sort the list", comment: "Tooltip"))
    }

    /// A toggle binding for membership of one element in one of the filter sets.
    private func member<Element: Hashable>(_ element: Element, of keyPath: WritableKeyPath<ExploreFilters, Set<Element>>) -> Binding<Bool> {
        Binding(get: { explore.filters[keyPath: keyPath].contains(element) },
                set: { on in
                    if on { explore.filters[keyPath: keyPath].insert(element) } else { explore.filters[keyPath: keyPath].remove(element) }
                })
    }
}
