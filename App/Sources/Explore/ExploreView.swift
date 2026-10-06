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
    @State private var choosingDay = false

    var body: some View {
        HSplitView {
            ExploreListPanel(explore: explore)
                .frame(minWidth: IterSize.listMin, idealWidth: IterSize.listIdeal, maxWidth: IterSize.listMax)
            ExploreMapPane(explore: explore)
                .frame(minWidth: IterSize.listMin, maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle(Text("Explore", comment: "Window title"))
        .searchable(text: $explore.query, placement: .toolbar,
                    prompt: Text("Search", comment: "Explore search field prompt"))
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
        ToolbarItem(placement: .primaryAction) { dateControl }
        if !explore.isToday {
            ToolbarItem(placement: .primaryAction) {
                Button(String(localized: "Today", comment: "Toolbar button: jump to today")) { explore.goToToday() }
                    .help(String(localized: "Jump to today", comment: "Tooltip"))
            }
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

    private static let utc = TimeZone(identifier: "UTC")!

    private var dayBinding: Binding<Date> {
        Binding(get: { explore.day.noon(in: Self.utc) }, set: { explore.day = LocalDay($0, in: Self.utc) })
    }

    /// "Mon, Oct 5"; the year is added only for a day outside the current year. UTC, like the day binding.
    private var dayLabel: String {
        let date = explore.day.noon(in: Self.utc)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.utc
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: model.now())
        var style = Date.FormatStyle().weekday(.abbreviated).month(.abbreviated).day()
        if !sameYear { style = style.year() }
        style.timeZone = Self.utc
        return date.formatted(style)
    }

    private var fullDayLabel: String {
        var style = Date.FormatStyle().weekday(.wide).month(.wide).day().year()
        style.timeZone = Self.utc
        return explore.day.noon(in: Self.utc).formatted(style)
    }

    /// One grouped control: previous day, the day (opens a calendar), next day.
    private var dateControl: some View {
        ControlGroup {
            Button {
                explore.shiftDay(by: -1)
            } label: {
                Label(String(localized: "Previous Day", comment: "Toolbar button"), systemImage: "chevron.left")
            }
            .keyboardShortcut("[", modifiers: .command)
            .help(String(localized: "Previous day (⌘[)", comment: "Tooltip"))

            Button {
                choosingDay.toggle()
            } label: {
                Text(dayLabel).monospacedDigit()
            }
            .help(String(localized: "\(fullDayLabel). Choose a day", comment: "Tooltip: the shown day, then a hint that it opens a calendar"))
            .accessibilityLabel(Text("Date", comment: "Accessibility label of the date control"))
            .accessibilityValue(Text(fullDayLabel))
            .popover(isPresented: $choosingDay, arrowEdge: .bottom) { dayPopover }

            Button {
                explore.shiftDay(by: 1)
            } label: {
                Label(String(localized: "Next Day", comment: "Toolbar button"), systemImage: "chevron.right")
            }
            .keyboardShortcut("]", modifiers: .command)
            .help(String(localized: "Next day (⌘])", comment: "Tooltip"))
        }
        .controlGroupStyle(.navigation)
    }

    private var dayPopover: some View {
        VStack(spacing: IterSpace.md) {
            DatePicker(selection: Binding(get: { dayBinding.wrappedValue },
                                          set: { dayBinding.wrappedValue = $0; choosingDay = false }),
                       displayedComponents: .date) {
                Text("Date", comment: "Accessibility label of the date picker")
            }
            .datePickerStyle(.graphical)
            .labelsHidden()
            .environment(\.timeZone, Self.utc)
            Button(String(localized: "Today", comment: "Button: jump to today")) {
                explore.goToToday()
                choosingDay = false
            }
            .disabled(explore.isToday)
            .help(String(localized: "Jump to today", comment: "Tooltip"))
        }
        .padding(IterSpace.md)
    }
}
