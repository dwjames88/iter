import SwiftUI
import IterCore
import IterData
import IterDesign
import IterFeatures

/// The content of the phone's bottom sheet and the iPad's panel column: the list state (title, round buttons, chip row,
/// banners, sections) and, once a place is open, its light panel. The list stays mounted underneath so its scroll
/// position survives.
struct ExploreBrowser: View {
    @Bindable var explore: ExploreModel
    /// A row was opened (the panel is showing).
    var onOpenPlace: () -> Void = {}

    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            listState
                .opacity(explore.showsPanel ? 0 : 1)
                .allowsHitTesting(!explore.showsPanel)
                .accessibilityHidden(explore.showsPanel)
            if explore.showsPanel, let row = explore.selectedRow {
                ExplorePlaceDetail(explore: explore, row: row)
                    .transition(reduceMotion ? .identity : .opacity)
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: explore.showsPanel)
        .task(id: explore.rows.map(\.id)) { explore.requestForecasts() }
    }

    // MARK: List state

    private var listState: some View {
        VStack(spacing: IterSpace.sm) {
            SheetTitleHeader(title: String(localized: "Explore", comment: "Explore sheet title"), subtitle: subtitle) {
                ExploreMoreMenu(explore: explore)
                shareButton
            }
            FullWidthSegmentedPicker(label: String(localized: "Sort", comment: "VoiceOver label of the Explore sort control"),
                                     options: sortOptions, selection: $explore.sort)
                .padding(.horizontal, IterSpace.lg)
            ChipRow(chips: chips)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    WeatherStatusBanner(status: explore.weatherStatus)
                    ExploreLocationBanner(explore: explore)
                    searchStatus
                    if explore.hasSampleScores { SampleDataLabel(style: .inline).padding(.horizontal, IterSpace.lg).padding(.top, IterSpace.sm) }
                    content
                    ForecastSourceLines(app: model, coordinates: explore.rows.filter { $0.score != nil }.map(\.spot.coordinate))
                        .padding(.horizontal, IterSpace.lg)
                        .padding(.vertical, IterSpace.lg)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.bottom, IterSpace.lg)
            }
            .scrollBounceBehavior(.basedOnSize)
            .accessibilityLabel(Text("Places", comment: "VoiceOver label of the Explore list"))
        }
    }

    private var subtitle: String {
        let n = explore.rows.count
        if explore.isLoadingForecasts { return String(localized: "Loading forecasts…", comment: "Explore sheet subtitle") }
        return n == 1 ? String(localized: "1 place", comment: "Explore sheet subtitle") : String(localized: "\(n) places", comment: "Explore sheet subtitle: number of places listed")
    }

    // MARK: Share

    @ViewBuilder private var shareButton: some View {
        if let url = shareURL {
            ShareLink(item: url, subject: Text("Explore", comment: "Share subject"),
                      message: Text("Light spots in this area", comment: "Share message")) {
                RoundGlassLabel(systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Share this area", comment: "VoiceOver"))
        } else {
            RoundGlassLabel(systemImage: "square.and.arrow.up").opacity(0.4)
                .accessibilityLabel(Text("Share this area", comment: "VoiceOver")).accessibilityAddTraits(.isButton)
                .accessibilityHint(Text("Available once the map has loaded", comment: "VoiceOver hint"))
        }
    }

    /// The visible map area as an Apple Maps link.
    private var shareURL: URL? {
        guard let r = explore.visibleRegion else { return nil }
        var c = URLComponents(string: "https://maps.apple.com/")!
        c.queryItems = [URLQueryItem(name: "ll", value: String(format: "%.5f,%.5f", r.center.latitude, r.center.longitude)),
                        URLQueryItem(name: "spn", value: String(format: "%.4f,%.4f", r.latitudeDelta, r.longitudeDelta))]
        return c.url
    }

    // MARK: Sort and filter chips (sort is the segmented control; chips are multi-select filters)

    private var sortOptions: [(value: ExploreSort, title: String)] {
        [(.distance, explore.hasLocation ? String(localized: "Near you", comment: "Sort segment: nearest first")
                                         : String(localized: "Nearest", comment: "Sort segment: nearest to the map centre first")),
         (.bestLight, String(localized: "Best light", comment: "Sort segment: by Light Index")),
         (.popularity, String(localized: "Popular", comment: "Sort segment: most popular first"))]
    }

    private var chips: [ChipItem] {
        var out: [ChipItem] = []
        for best in [BestLight.sunrise, .sunset] {
            let on = explore.filters.bestLight.contains(best)
            out.append(ChipItem(id: "best-\(best.rawValue)", title: LightText.name(best), symbol: LightText.symbol(best == .sunrise ? LightIntent.sunrise : .sunset),
                                isSelected: on) {
                if on { explore.filters.bestLight.remove(best) } else { explore.filters.bestLight.insert(best) }
            })
        }
        for category in SpotCategory.allCases {
            let on = explore.filters.categories.contains(category)
            out.append(ChipItem(id: "cat-\(category.rawValue)", title: LightText.name(category), symbol: nil, isSelected: on) {
                if on { explore.filters.categories.remove(category) } else { explore.filters.categories.insert(category) }
            })
        }
        return out
    }

    // MARK: Status

    @ViewBuilder private var searchStatus: some View {
        switch explore.searchState {
        case .searching(let query):
            HStack(spacing: IterSpace.sm) {
                ProgressView().controlSize(.small)
                Text(LightText.searchingApple).font(.footnote).foregroundStyle(IterColor.textSecondary)
                Spacer(minLength: 0)
                Button(String(localized: "Cancel", comment: "Button")) { explore.cancelSearch() }.font(.footnote)
            }
            .padding(.horizontal, IterSpace.lg).padding(.vertical, IterSpace.sm)
            .accessibilityLabel(LightText.searchingApple + " " + query)
        case .failed(let query):
            HStack(spacing: IterSpace.sm) {
                Label(LightText.searchFailed(query), systemImage: "exclamationmark.triangle")
                    .font(.footnote).foregroundStyle(IterColor.warning)
                Spacer(minLength: 0)
                Button(String(localized: "Retry", comment: "Button")) { explore.searchAppleMaps() }.font(.footnote)
            }
            .padding(.horizontal, IterSpace.lg).padding(.vertical, IterSpace.sm)
        case .idle, .finished:
            EmptyView()
        }
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        if explore.rows.isEmpty, !explore.searchState.isSearching, !explore.hasAskContent {
            VStack(spacing: IterSpace.sm) {
                if !explore.searchSuggestions.isEmpty {
                    ExploreSuggestionsView(suggestions: explore.searchSuggestions) { explore.run($0) }
                        .padding(.horizontal, IterSpace.lg)
                }
                emptyState
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                if !explore.searchSuggestions.isEmpty {
                    ExploreSuggestionsView(suggestions: explore.searchSuggestions) { explore.run($0) }
                        .padding(.horizontal, IterSpace.lg)
                }
                ExploreAskBlock(explore: explore, onOpen: open)
                ForEach(explore.sections.filter { $0.kind != .ask }) { section in
                    sectionView(section)
                }
            }
        }
    }

    @ViewBuilder private var emptyState: some View {
        if case .finished(_, 0) = explore.searchState, explore.rows.isEmpty {
            ContentUnavailableView {
                Label(String(localized: "No places found", comment: "Empty state after a real Apple Maps search"), systemImage: "mappin.slash")
            } description: {
                Text(LightText.noPlaces(explore.query.trimmingCharacters(in: .whitespacesAndNewlines)))
            } actions: {
                if explore.isNarrowed { Button(String(localized: "Clear filters", comment: "Button")) { explore.clearFilters() } }
            }
        } else {
            ContentUnavailableView {
                Label(String(localized: "No spots here", comment: "Empty state title"), systemImage: "line.3.horizontal.decrease.circle")
            } description: {
                Text("Nothing fits the current search and filters. Try clearing them.", comment: "Empty state description")
            } actions: {
                Button(String(localized: "Clear filters", comment: "Button")) { explore.clearFilters() }
            }
        }
    }

    private func open(_ row: ExploreRow) {
        explore.select(row.id, from: .list)
        explore.openPanel()
        onOpenPlace()
    }

    private func sectionTitle(_ section: ExploreSection) -> String {
        section.kind == .nearYou ? LightText.nearYouTitle(radiusMiles: explore.radiusMiles) : LightText.name(section.kind)
    }

    @ViewBuilder private func sectionView(_ section: ExploreSection) -> some View {
        let isMore = section.kind == .morePlaces
        let showsRows = !isMore || explore.isMorePlacesOpen
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if isMore { withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) { explore.setMorePlacesOpen(!explore.isMorePlacesOpen) } }
            } label: {
                HStack(spacing: IterSpace.sm) {
                    if isMore { Image(systemName: showsRows ? "chevron.down" : "chevron.right").imageScale(.small) }
                    Text(sectionTitle(section))
                    Spacer()
                    Text(section.rows.count, format: .number).monospacedDigit()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(IterColor.textSecondary)
                .padding(.horizontal, IterSpace.lg)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!isMore)
            .accessibilityAddTraits(.isHeader)
            .accessibilityValue(isMore ? (showsRows ? Text("Expanded", comment: "VoiceOver") : Text("Collapsed", comment: "VoiceOver")) : Text(verbatim: ""))
            if showsRows {
                ForEach(section.rows) { row in
                    ExploreRowButton(explore: explore, row: row) { open(row) }
                }
            }
        }
        .padding(.top, IterSpace.sm)
    }
}

/// One tappable list row: the shared row view, a selected wash, the spot's context menu, forecasts on appear.
struct ExploreRowButton: View {
    @Bindable var explore: ExploreModel
    let row: ExploreRow
    let action: () -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        Button(action: action) {
            ExploreRowView(row: row, showsDistance: explore.hasLocation)
                .padding(.horizontal, IterSpace.lg)
                .frame(minHeight: 56)
                .background(explore.selectedID == row.id ? IterColor.backgroundModule : Color.clear)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onAppear { explore.requestForecast(for: row.id) }
        .contextMenu { ExploreSpotMenu(spot: row.spot, day: row.day ?? model.today(in: row.spot.timeZone)) }
    }
}

/// The Ask section for iOS: the shared section while it runs or fails; when it has results, the same header and rows as
/// tappable buttons (the shared section's rows are selectable only in a macOS list).
struct ExploreAskBlock: View {
    @Bindable var explore: ExploreModel
    let onOpen: (ExploreRow) -> Void

    private var results: [ExploreRow] { explore.sections.first { $0.kind == .ask }?.rows ?? [] }

    var body: some View {
        if explore.hasAskContent {
            if case .results = explore.askState {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: IterSpace.xxs) {
                        HStack {
                            Label(LightText.name(.ask), systemImage: "sparkles")
                            Spacer()
                            Text(results.count, format: .number).monospacedDigit()
                        }
                        .font(.subheadline.weight(.semibold))
                        Text(LightText.askRequest(explore.askSubmittedRequest)).font(.footnote).lineLimit(2)
                    }
                    .foregroundStyle(IterColor.textSecondary)
                    .padding(.horizontal, IterSpace.lg)
                    .padding(.top, IterSpace.sm)
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)
                    ForEach(results) { row in
                        Button { onOpen(row) } label: {
                            ExploreAskRow(row: row, showsDistance: explore.hasLocation)
                                .padding(.horizontal, IterSpace.lg)
                                .background(explore.selectedID == row.id ? IterColor.backgroundModule : Color.clear)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .onAppear { explore.requestForecast(for: row.id) }
                    }
                    Text(LightText.askSourceLine)
                        .font(.footnote).foregroundStyle(IterColor.textTertiary)
                        .padding(.horizontal, IterSpace.lg).padding(.vertical, IterSpace.sm)
                }
                .padding(.bottom, IterSpace.sm)
            } else {
                ExploreAskSection(explore: explore).padding(.horizontal, IterSpace.lg).padding(.vertical, IterSpace.sm)
            }
        }
    }
}
