import SwiftUI
import IterCore
import IterDesign
import IterFeatures

/// The search tab (iOS 26 `Tab(role: .search)`): Apple Maps and Ask suggestions and results. OWNER: Explore.
/// `onShowPlace` is called after a result is selected in the shared ExploreModel, so the shell can switch to Explore.
struct ExploreSearchScreen: View {
    var onShowPlace: () -> Void = {}
    @Environment(ExploreModel.self) private var explore
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var explore = explore
        ScrollView {
            VStack(alignment: .leading, spacing: IterSpace.md) {
                if trimmed.isEmpty {
                    emptyState
                } else {
                    if !explore.searchSuggestions.isEmpty {
                        ExploreSuggestionsView(suggestions: explore.searchSuggestions, promptPrefix: explore.activePromptPrefix) { explore.run($0) }
                            .padding(.horizontal, IterSpace.lg)
                    }
                    progress
                    ExploreAskBlock(explore: explore, onOpen: show)
                    ForEach(explore.sections.filter { $0.kind != .ask }) { section in
                        VStack(alignment: .leading, spacing: 0) {
                            HStack {
                                Text(section.kind == .nearYou ? LightText.nearYouTitle(radiusMiles: explore.radiusMiles) : LightText.name(section.kind))
                                Spacer()
                                Text(section.rows.count, format: .number).monospacedDigit()
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(IterColor.textSecondary)
                            .padding(.horizontal, IterSpace.lg)
                            .frame(minHeight: 36)
                            .accessibilityAddTraits(.isHeader)
                            ForEach(section.rows) { row in
                                ExploreRowButton(explore: explore, row: row) { show(row) }
                            }
                        }
                    }
                }
            }
            .padding(.vertical, IterSpace.sm)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(IterColor.backgroundContent)
        .navigationTitle(String(localized: "Search", comment: "Search tab title"))
        .searchable(text: $explore.query, prompt: Text("Search places or ask Iter", comment: "Explore search field prompt"))
        .onSubmit(of: .search) { explore.submitSearch() }
        .task(id: explore.rows.map(\.id)) { explore.requestForecasts() }
    }

    private var trimmed: String { explore.query.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func show(_ row: ExploreRow) {
        explore.select(row.id, from: .list)
        explore.openPanel()
        onShowPlace()
    }

    @ViewBuilder private var progress: some View {
        switch explore.searchState {
        case .searching:
            HStack(spacing: IterSpace.sm) {
                ProgressView().controlSize(.small)
                Text(LightText.searchingApple).font(.footnote).foregroundStyle(IterColor.textSecondary)
            }
            .padding(.horizontal, IterSpace.lg)
        case .failed(let query):
            HStack {
                Label(LightText.searchFailed(query), systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(IterColor.warning)
                Spacer()
                Button(String(localized: "Retry", comment: "Button")) { explore.searchAppleMaps() }.font(.footnote)
            }
            .padding(.horizontal, IterSpace.lg)
        case .finished(_, 0) where explore.rows.isEmpty:
            Text(LightText.noPlaces(trimmed)).font(.subheadline).foregroundStyle(IterColor.textSecondary).padding(.horizontal, IterSpace.lg)
        default:
            EmptyView()
        }
    }

    private var emptyState: some View {
        VStack(spacing: IterSpace.sm) {
            Image(systemName: "magnifyingglass").font(.system(size: 34)).foregroundStyle(IterColor.textTertiary)
            Text("Search or ask", comment: "Search tab empty state title").font(.title3.weight(.semibold))
            Text("Find a place on Apple Maps, or ask for light, like \"foggy forest within two hours\".", comment: "Search tab empty state detail")
                .font(.subheadline).foregroundStyle(IterColor.textSecondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, IterSpace.xl)
        .padding(.top, 80)
    }
}
