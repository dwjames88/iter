import SwiftUI
import AppKit
import IterCore
import IterData
import IterDesign
import IterFeatures

/// The leading column, in two states. The list: summary, honest notices, search status, the list, and the forecast
/// source. Or, once a place is opened, that place's light panel (`ExploreLightPanel`) in its place. The list stays
/// mounted underneath, hidden, so its scroll position survives.
struct ExploreListPanel: View {
    @Bindable var explore: ExploreModel
    @Environment(AppModel.self) private var model
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var listFocused: Bool
    /// A click waits out the double-click interval before it opens the panel, so a double-click can open the spot page.
    @State private var pendingOpen: Task<Void, Never>?
    /// A double-click's second click must not schedule the panel again after the spot page opened.
    @State private var openSuppressedUntil = Date.distantPast
    @State private var didInitialScroll = false
    /// True for a few seconds after the launch scroll, while regrouping (the location fix) may still move rows.
    @State private var launchScrollSettling = false

    /// Launch-hook timing: wait for the rows to lay out, and how long regrouping may re-issue the scroll.
    private enum LaunchScroll {
        static let layoutDelay = Duration.milliseconds(200)
        static let settleWindow = Duration.seconds(4)
    }

    /// Changes whenever rows move between or within sections.
    private var rowLayoutSignature: [String] { explore.sections.flatMap { $0.rows.map(\.id) } }

    /// Runs a model change that opens or closes a row, animated unless Reduce Motion is on.
    private func animated(_ change: () -> Void) {
        if reduceMotion { change() } else { withAnimation(.snappy(duration: 0.2)) { change() } }
    }

    var body: some View {
        ZStack {
            listState
                .opacity(explore.showsPanel ? 0 : 1)
                .allowsHitTesting(!explore.showsPanel)
                .accessibilityHidden(explore.showsPanel)
            if explore.showsPanel, let row = explore.selectedRow {
                ExploreLightPanel(explore: explore, row: row)
                    .transition(reduceMotion ? .identity : .move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: explore.showsPanel)
        .onChange(of: explore.showsPanel) { _, shows in
            // Back: the list takes the keyboard again, the row still selected.
            if !shows { listFocused = true } else { pendingOpen?.cancel() }
        }
    }

    private var listState: some View {
        VStack(spacing: 0) {
            header
            Divider()
            WeatherStatusBanner(status: explore.weatherStatus)
            ExploreLocationBanner(explore: explore)
            content
            Divider()
            ForecastSourceLines(app: model, coordinates: explore.rows.filter { $0.score != nil }.map(\.spot.coordinate))
                .padding(.horizontal, IterSpace.md)
                .padding(.vertical, IterSpace.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: .infinity)
        .background(IterColor.backgroundContent, ignoresSafeAreaEdges: [])
    }

    // MARK: Opening the panel

    private var isKeyEvent: Bool { NSApp.currentEvent?.type == .keyDown }

    /// A click selected `id`: the panel opens after the double-click interval unless a double-click arrives first.
    private func scheduleOpen(_ id: String) {
        pendingOpen?.cancel()
        guard Date() >= openSuppressedUntil else { return }
        pendingOpen = Task {
            try? await Task.sleep(for: .seconds(NSEvent.doubleClickInterval))
            guard !Task.isCancelled, explore.selectedID == id else { return }
            explore.openPanel()
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: IterSpace.sm) {
            HStack(spacing: IterSpace.xs) {
                Text(InflectedCount.string("place", count: explore.rows.count) { AttributedString(localized: "^[\(explore.rows.count) place](inflect: true)", comment: "Number of places listed in Explore") })
                    .font(IterFont.subheadline)
                Spacer(minLength: 0)
                if explore.isLoadingForecasts {
                    ProgressView().controlSize(.small)
                        .help(String(localized: "Loading forecasts", comment: "Tooltip on the progress indicator"))
                }
                optionsMenu
            }
            .font(IterFont.subheadline)
            .foregroundStyle(IterColor.textSecondary)

            if explore.hasSampleScores { SampleDataLabel(style: .inline) }
            searchStatus
        }
        .padding(.horizontal, IterSpace.md)
        .padding(.vertical, IterSpace.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Options menu

    /// Near You radius, sort and filters in one menu, labelled with the filter icon and the active count.
    private var optionsMenu: some View {
        Menu {
            Picker(selection: radiusBinding) {
                ForEach(UserLocationModel.radiusChoices, id: \.self) { miles in
                    Text(LightText.radiusChoice(miles)).tag(miles)
                }
            } label: {
                Text(LightText.nearYouRadius)
            }
            .pickerStyle(.inline)
            Picker(selection: $explore.sort) {
                ForEach(ExploreSort.allCases) { sort in Text(LightText.name(sort)).tag(sort) }
            } label: {
                Text("Sort By", comment: "Menu section title")
            }
            .pickerStyle(.inline)
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
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Sort and filters", comment: "Explore list header menu"))
            .accessibilityValue(count > 0 ? Text("\(count) filters active", comment: "VoiceOver: number of active filters") : Text("No filters active", comment: "VoiceOver"))
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(String(localized: "Sort the list and filter by category, what a spot is known for, and source", comment: "Tooltip"))
    }

    private var radiusBinding: Binding<Int> {
        Binding(get: { model.location.radiusMiles }, set: { model.location.radiusMiles = $0 })
    }

    /// A toggle binding for membership of one element in one of the filter sets.
    private func member<Element: Hashable>(_ element: Element, of keyPath: WritableKeyPath<ExploreFilters, Set<Element>>) -> Binding<Bool> {
        Binding(get: { explore.filters[keyPath: keyPath].contains(element) },
                set: { on in
                    if on { explore.filters[keyPath: keyPath].insert(element) } else { explore.filters[keyPath: keyPath].remove(element) }
                })
    }

    private var trimmedQuery: String { explore.query.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Offer, progress, failure: one slot under the summary. "No places found" appears only after a real search.
    @ViewBuilder private var searchStatus: some View {
        switch explore.searchState {
        case .searching(let query):
            HStack(spacing: IterSpace.sm) {
                ProgressView().controlSize(.small)
                Text(LightText.searchingApple).font(IterFont.caption).foregroundStyle(IterColor.textSecondary)
                Spacer(minLength: 0)
                Button(String(localized: "Cancel", comment: "Button")) { explore.cancelSearch() }
                    .controlSize(.small)
            }
            .accessibilityLabel(LightText.searchingApple + " " + query)
        case .failed(let query):
            HStack(alignment: .firstTextBaseline, spacing: IterSpace.sm) {
                Label(LightText.searchFailed(query), systemImage: "exclamationmark.triangle")
                    .font(IterFont.caption)
                    .foregroundStyle(IterColor.warning)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button(String(localized: "Retry", comment: "Button")) { explore.searchAppleMaps() }
                    .controlSize(.small)
            }
        case .idle, .finished:
            EmptyView()
        }
    }

    // MARK: List

    @ViewBuilder private var content: some View {
        if explore.rows.isEmpty, !explore.searchState.isSearching, !explore.hasAskContent {
            VStack(spacing: 0) {
                if !explore.searchSuggestions.isEmpty {
                    ExploreSuggestionsView(suggestions: explore.searchSuggestions) { explore.run($0) }
                        .padding(.horizontal, IterSpace.md)
                        .padding(.vertical, IterSpace.sm)
                    Divider()
                }
                emptyState
            }
        } else {
            list
        }
    }

    /// A selection made with the arrow keys opens the panel at once; one made with the mouse selects now and opens
    /// after the double-click interval (the row's tap, below).
    private var selection: Binding<String?> {
        Binding(get: { explore.selectedID }, set: { id in
            let changed = id != explore.selectedID
            explore.select(id, from: isKeyEvent ? .keyboard : .list)
            guard changed, let id else { return }
            if isKeyEvent { explore.openPanel() } else { scheduleOpen(id) }
        })
    }

    private var moreExpanded: Binding<Bool> {
        Binding(get: { explore.isMorePlacesOpen }, set: { explore.setMorePlacesOpen($0) })
    }

    private func sectionTitle(_ section: ExploreSection) -> String {
        section.kind == .nearYou ? LightText.nearYouTitle(radiusMiles: explore.radiusMiles) : LightText.name(section.kind)
    }

    @ViewBuilder private func sectionHeader(_ section: ExploreSection) -> some View {
        if section.kind == .morePlaces {
            // The inset list draws no disclosure control of its own, so the header carries one.
            let open = explore.isMorePlacesOpen
            HStack(spacing: IterSpace.xs) {
                Image(systemName: open ? "chevron.down" : "chevron.right")
                    .imageScale(.small)
                    .frame(width: IterSize.iconSmall)
                headerLabel(section)
            }
            .contentShape(Rectangle())
            .onTapGesture { animated { explore.setMorePlacesOpen(!open) } }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityValue(open ? Text("Expanded", comment: "VoiceOver: the section is open") : Text("Collapsed", comment: "VoiceOver: the section is closed"))
            .font(IterFont.moduleTitle)
            .foregroundStyle(IterColor.textSecondary)
            .padding(.top, IterSpace.sm)
            .padding(.bottom, IterSpace.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(IterColor.backgroundContent)
        } else {
            headerLabel(section)
                .font(IterFont.moduleTitle)
                .foregroundStyle(IterColor.textSecondary)
                .padding(.top, IterSpace.sm)
                .padding(.bottom, IterSpace.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(IterColor.backgroundContent)
                .accessibilityElement(children: .combine)
        }
    }

    /// 24 pt between one section and the next header (HIERARCHY.md); none after the last, none inside a pinned header.
    @ViewBuilder private func sectionGap(after section: ExploreSection) -> some View {
        if section.id != explore.sections.last?.id {
            Color.clear.frame(height: IterSpace.xl).accessibilityHidden(true)
        }
    }

    private func headerLabel(_ section: ExploreSection) -> some View {
        HStack {
            Text(sectionTitle(section))
            Spacer()
            Text(section.rows.count, format: .number).monospacedDigit()
        }
    }

    /// One row per spot. A click selects it (the list's selection, so its pin is highlighted) and opens its panel.
    @ViewBuilder private func rows(in section: ExploreSection) -> some View {
        ForEach(section.rows) { row in
            ExploreRowView(row: row, showsDistance: explore.hasLocation)
                .equatable()
                .id(row.id)
                .tag(row.id)
                .onAppear { explore.requestForecast(for: row.id) }
                // Also when the row is already selected (after Back), which changes no selection.
                .simultaneousGesture(TapGesture().onEnded { scheduleOpen(row.id) })
                .onHover { inside in
                    if inside { explore.hoveredID = row.id } else if explore.hoveredID == row.id { explore.hoveredID = nil }
                }
        }
    }

    /// The collapsible "More places" section is always last, and the expandable `Section` takes no footer.
    @ViewBuilder private func listSection(_ section: ExploreSection) -> some View {
        if section.kind == .morePlaces {
            Section(isExpanded: moreExpanded) {
                rows(in: section)
            } header: {
                sectionHeader(section)
            }
        } else {
            Section {
                rows(in: section)
            } header: {
                sectionHeader(section)
            } footer: {
                sectionGap(after: section)
            }
        }
    }

    @ViewBuilder private var list: some View {
        let _ = IterPerf.count("list.body")
        ScrollViewReader { proxy in
            List(selection: selection) {
                if !explore.searchSuggestions.isEmpty {
                    ExploreSuggestionsView(suggestions: explore.searchSuggestions) { explore.run($0) }
                }
                if explore.hasAskContent { ExploreAskSection(explore: explore) }
                ForEach(explore.sections.filter { $0.kind != .ask }) { section in
                    listSection(section)
                }
            }
            .listStyle(.inset)
            .layoutGrid(lanes: LayoutLane.eventRow())
            .paperListBackground()
            .contextMenu(forSelectionType: String.self) { ids in
                if let id = ids.first, let row = explore.row(id: id) {
                    ExploreSpotMenu(spot: row.spot, day: row.day ?? model.today(in: row.spot.timeZone))
                }
            } primaryAction: { ids in
                guard let id = ids.first, let row = explore.row(id: id) else { return }
                pendingOpen?.cancel()
                if isKeyEvent {
                    // Return opens the panel.
                    explore.select(id, from: .keyboard)
                    explore.openPanel()
                } else {
                    // Double-click opens the spot page.
                    openSuppressedUntil = Date().addingTimeInterval(NSEvent.doubleClickInterval)
                    ExploreActions.open(row.spot, day: row.day ?? model.today(in: row.spot.timeZone), navigation: navigation)
                }
            }
            .focused($listFocused)
            .onAppear {
                // `-IterSelectRow` (and the snapshot tests) ask for one program scroll when the list is first built.
                if AppLaunch.selectRowID != nil || AppLaunch.isRunningTests, !didInitialScroll, let target = explore.scrollRequest?.target {
                    didInitialScroll = true
                    if AppLaunch.selectRowID != nil {
                        launchScrollSettling = true
                        Task {
                            await scrollAfterLayout(proxy, to: target)
                            try? await Task.sleep(for: LaunchScroll.settleWindow)
                            launchScrollSettling = false
                        }
                    } else {
                        proxy.scrollTo(target, anchor: .center)
                    }
                }
            }
            .onChange(of: rowLayoutSignature) {
                // Sections regroup when the location fix arrives; put the launch row back at the top. Launch hook only.
                guard launchScrollSettling, let target = explore.scrollRequest?.target else { return }
                Task { await scrollAfterLayout(proxy, to: target) }
            }
            .onChange(of: explore.scrollRequest?.id) {
                if let target = explore.scrollRequest?.target { withAnimation { proxy.scrollTo(target) } }
            }
            .accessibilityLabel(Text("Places", comment: "VoiceOver label of the Explore list"))
        }
    }

    /// Waits for the rows to lay out, then puts the row at the top.
    private func scrollAfterLayout(_ proxy: ScrollViewProxy, to target: String) async {
        try? await Task.sleep(for: LaunchScroll.layoutDelay)
        // Anchored at the top, the row would sit under the pinned section header. Put the row before it at the top
        // instead, so the header covers that one and the row below it is fully visible.
        let ids = explore.rows.map(\.id)
        if let index = ids.firstIndex(of: target), index > 0 {
            proxy.scrollTo(ids[index - 1], anchor: .top)
        } else {
            proxy.scrollTo(target, anchor: .top)
        }
    }

    @ViewBuilder private var emptyState: some View {
        emptyContent.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private var emptyContent: some View {
        if case .finished(_, 0) = explore.searchState, explore.rows.isEmpty {
            ContentUnavailableView {
                Label(String(localized: "No places found", comment: "Empty state after a real Apple Maps search"),
                      systemImage: "mappin.slash")
            } description: {
                Text(LightText.noPlaces(trimmedQuery))
            } actions: {
                if explore.isNarrowed {
                    Button(String(localized: "Clear Filters", comment: "Button")) { explore.clearFilters() }
                }
            }
        } else {
            ContentUnavailableView {
                Label(String(localized: "No Matching Spots", comment: "Empty state title"), systemImage: "line.3.horizontal.decrease.circle")
            } description: {
                Text("Nothing fits the current search and filters.", comment: "Empty state description")
            } actions: {
                Button(String(localized: "Clear Filters", comment: "Button")) { explore.clearFilters() }
            }
        }
    }
}
