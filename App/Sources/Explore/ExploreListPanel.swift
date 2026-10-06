import SwiftUI
import IterCore
import IterData
import IterDesign
import IterFeatures

/// The leading column: summary, honest notices, search status, the list, and the forecast source with its attribution.
struct ExploreListPanel: View {
    @Bindable var explore: ExploreModel
    @Environment(AppModel.self) private var model
    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            ForecastSourceFooter(app: model, coordinates: explore.rows.filter { $0.score != nil }.map(\.spot.coordinate))
                .padding(.horizontal, IterSpace.md)
                .padding(.vertical, IterSpace.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: .infinity)
        .background(IterColor.backgroundContent, ignoresSafeAreaEdges: [])
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: IterSpace.sm) {
            HStack(spacing: IterSpace.xs) {
                Text("^[\(explore.rows.count) place](inflect: true)", comment: "Number of places listed in Explore")
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
            if let reason = explore.forecastNotice {
                Label {
                    Text(LightText.noForecastReason(reason))
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "thermometer.medium.slash")
                }
                .font(IterFont.caption)
                .foregroundStyle(IterColor.textSecondary)
            }
            searchStatus
        }
        .padding(.horizontal, IterSpace.md)
        .padding(.vertical, IterSpace.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Options menu

    /// Light, sort and filters in one menu, labelled with the current light choice.
    private var optionsMenu: some View {
        @Bindable var model = model
        return Menu {
            Picker(selection: $model.preferredIntent) {
                Text(LightText.eachSpotsBest).tag(LightIntent?.none)
                Divider()
                ForEach(LightIntent.allCases) { intent in
                    Label(LightText.name(intent), systemImage: LightText.symbol(intent)).tag(LightIntent?.some(intent))
                }
            } label: {
                Text("Show Light For", comment: "Menu section title: which light to score every spot for")
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
                Text(model.preferredIntent.map { LightText.name($0) } ?? LightText.eachSpotsBest)
                Image(systemName: count > 0 ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                if count > 0 { Text(count, format: .number).monospacedDigit() }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Light, sort and filters", comment: "Explore list header menu"))
            .accessibilityValue(count > 0 ? Text("\(count) filters active", comment: "VoiceOver: number of active filters") : Text("No filters active", comment: "VoiceOver"))
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(String(localized: "Choose the light, sort the list, and filter by category, what a spot is known for, and source", comment: "Tooltip"))
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
                Button(String(localized: "Retry", comment: "Button")) { explore.submitSearch() }
                    .controlSize(.small)
            }
        case .idle, .finished:
            if !trimmedQuery.isEmpty, !isSearched(trimmedQuery) {
                Button {
                    explore.submitSearch()
                } label: {
                    Label(LightText.searchApple(trimmedQuery), systemImage: "magnifyingglass")
                        .lineLimit(1)
                }
                .buttonStyle(.link)
                .font(IterFont.caption)
            }
        }
    }

    private func isSearched(_ query: String) -> Bool {
        if case .finished(let q, _) = explore.searchState { return q == query }
        return false
    }

    // MARK: List

    @ViewBuilder private var content: some View {
        if explore.rows.isEmpty, !explore.searchState.isSearching {
            emptyState
        } else {
            list
        }
    }

    private var selection: Binding<String?> {
        Binding(get: { explore.selectedID }, set: { explore.select($0, from: .list) })
    }

    private var list: some View {
        ScrollViewReader { proxy in
            List(selection: selection) {
                ForEach(explore.sections) { section in
                    Section {
                        ForEach(section.rows) { row in
                            ExploreRowView(row: row, isHovered: explore.hoveredID == row.id)
                                .onHover { inside in
                                    if inside { explore.hoveredID = row.id } else if explore.hoveredID == row.id { explore.hoveredID = nil }
                                }
                        }
                    } header: {
                        HStack {
                            Text(LightText.name(section.kind))
                            Spacer()
                            Text(section.rows.count, format: .number).monospacedDigit()
                        }
                        .font(IterFont.captionStrong)
                        .foregroundStyle(IterColor.textSecondary)
                    }
                }
            }
            .listStyle(.inset)
            .paperListBackground()
            .contextMenu(forSelectionType: String.self) { ids in
                if let id = ids.first, let row = explore.row(id: id) {
                    ExploreSpotMenu(spot: row.spot, day: explore.day)
                }
            } primaryAction: { ids in
                // Return and double-click open the spot page.
                if let id = ids.first, let row = explore.row(id: id) {
                    ExploreActions.open(row.spot, day: explore.day, navigation: navigation)
                }
            }
            .onChange(of: explore.scrollRequest?.id) {
                if let target = explore.scrollRequest?.target { withAnimation { proxy.scrollTo(target) } }
            }
            .accessibilityLabel(Text("Places", comment: "VoiceOver label of the Explore list"))
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

/// One list row: the spot, then its light on the chosen day (badge with window and score, and the window's start).
struct ExploreRowView: View {
    let row: ExploreRow
    var isHovered = false

    var body: some View {
        HStack(alignment: .center, spacing: IterSpace.md) {
            VStack(alignment: .leading, spacing: IterSpace.xxs) {
                Text(row.spot.name)
                    .font(IterFont.bodyEmphasis)
                    .foregroundStyle(IterColor.textPrimary)
                    .lineLimit(1)
                HStack(spacing: IterSpace.xs) {
                    Text(row.spot.locality)
                        .lineLimit(1)
                    if row.source == .yours {
                        ProvenanceTag(origin: .user)
                    }
                }
                .font(IterFont.caption)
                .foregroundStyle(IterColor.textSecondary)
            }
            Spacer(minLength: IterSpace.sm)
            light
        }
        .padding(.vertical, IterSpace.xs)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(LightText.rowDescription(row))
    }

    @ViewBuilder private var light: some View {
        if let window = row.window {
            VStack(alignment: .leading, spacing: IterSpace.xxs) {
                LightBadge(window: window, style: .regular, showsSource: false)
                if let time = LightText.startTime(window, in: row.spot.timeZone) {
                    Text(time)
                        .font(IterFont.timeSmall)
                        .foregroundStyle(IterColor.textSecondary)
                        .monospacedDigit()
                }
            }
        } else {
            Text(LightText.noWindowToday)
                .font(IterFont.caption)
                .foregroundStyle(IterColor.textSecondary)
        }
    }
}
