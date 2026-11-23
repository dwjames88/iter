import SwiftUI
import IterFeatures
import IterModel
import IterDiscovery
import IterUI

/// The card's header, as Maps titles its cards: a bold title with a quiet line under it and 32 pt glass circles in the corner.
struct FindCardHeader<Accessory: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(alignment: .top, spacing: IterSpace.sm) {
            VStack(alignment: .leading, spacing: IterSpace.xxs) {
                Text(verbatim: title)
                    .font(IterFont.titleSection)
                    .foregroundStyle(IterColor.textPrimary)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle, !subtitle.isEmpty {
                    Text(verbatim: subtitle)
                        .font(IterFont.secondary)
                        .foregroundStyle(IterColor.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: GlassCircleButtonStyle.size)
            GlassEffectContainer(spacing: IterSpace.sm) {
                HStack(spacing: IterSpace.sm) { accessory }
                    .buttonStyle(GlassCircleButtonStyle())
                    .menuStyle(.button)
                    .menuIndicator(.hidden)
            }
            .fixedSize()
        }
        .padding(.leading, IterSpace.lg)
        .padding(.top, IterSpace.lg)
        .padding(.trailing, GlassCircleButtonStyle.inset)
        .padding(.bottom, IterSpace.sm)
    }
}

/// The ordering menu: Popular, Unique or Mixed. Re-orders the places already found; nothing is fetched again.
struct FindOrderMenu: View {
    @Binding var ordering: DiscoveryOrdering

    var body: some View {
        Menu {
            Picker("Order Places", selection: $ordering) {
                Text("Popular").tag(DiscoveryOrdering.popular)
                Text("Unique").tag(DiscoveryOrdering.unique)
                Text("Mixed").tag(DiscoveryOrdering.mixed)
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            Label("Order Places", systemImage: "line.3.horizontal.decrease")
        }
        .help("Order places: Popular, Unique or Mixed")
    }
}

/// The discovery card: streaming results as they arrive, the progress line and per-source list, filters and ordering.
struct FindResultsCard: View {
    @Bindable var model: FindModel
    var showsSearchHere = false
    var initiallyShowsSources = false

    private var selection: Binding<String?> {
        Binding(get: { model.selectedID }, set: { model.select($0) })
    }

    private var title: String {
        if model.phase == .discovering, model.rows.isEmpty { return "Searching" }
        return FindText.resultCount(model.rows.count)
    }

    var body: some View {
        VStack(spacing: 0) {
            FindCardHeader(title: title, subtitle: model.area?.name) {
                FindOrderMenu(ordering: $model.ordering)
                Button { model.clear() } label: { Label("Close", systemImage: "xmark") }
                    .help("Clear the search")
            }
            if showsSearchHere {
                FindSearchHereButton { model.searchHere() }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, IterSpace.lg)
                    .padding(.bottom, IterSpace.sm)
            }
            List(selection: selection) {
                top
                if model.rows.isEmpty { empty } else {
                    ForEach(model.rows) { row in
                        FindRowView(row: row, locality: model.area?.name ?? "")
                            .equatable()
                            .tag(row.id)
                            .listRowSeparator(.visible)
                    }
                }
                footer
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    @ViewBuilder private var top: some View {
        Group {
            if let plan = FindText.planLine(label: model.planLabel, isBasic: model.isBasicSearch) {
                FindPlanLine(text: plan, isBasic: model.isBasicSearch)
            }
            FindProgressSection(progress: model.progress, phase: model.phase, chips: model.chips, isExpanded: initiallyShowsSources) {
                model.cancel()
            }
            if model.kindFilters.count > 1 {
                FindFilterChips(filters: model.kindFilters) { model.toggleKind($0) }
            }
            if let notice = model.notice {
                Text(verbatim: notice).font(IterFont.caption).foregroundStyle(IterColor.textSecondary)
            }
        }
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    @ViewBuilder private var empty: some View {
        if model.phase == .discovering {
            Text("Places appear here as sources answer.")
                .font(IterFont.secondary)
                .foregroundStyle(IterColor.textSecondary)
                .listRowSeparator(.hidden)
        } else {
            VStack(alignment: .leading, spacing: IterSpace.xs) {
                if case .failed(let why) = model.phase {
                    Text("The search could not run").font(IterFont.headline)
                    Text(verbatim: why).font(IterFont.secondary).foregroundStyle(IterColor.textSecondary)
                } else {
                    Text("No places found").font(IterFont.headline)
                    Text("Try a wider area or different words. The sources above show which ones answered.")
                        .font(IterFont.secondary).foregroundStyle(IterColor.textSecondary)
                }
            }
            .padding(.vertical, IterSpace.sm)
            .listRowSeparator(.hidden)
        }
    }

    @ViewBuilder private var footer: some View {
        let notes = footerNotes
        if !notes.isEmpty {
            VStack(alignment: .leading, spacing: IterSpace.xs) {
                ForEach(notes, id: \.self) { Text(verbatim: $0) }
            }
            .font(IterFont.caption)
            .foregroundStyle(IterColor.textTertiary)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
    }

    private var footerNotes: [String] {
        var out: [String] = []
        if let basis = model.area?.basisText { out.append("Area: " + basis) }
        if model.widened { out.append("Few places matched closely, so related subjects were added.") }
        if model.droppedCount > 0 {
            out.append(model.droppedCount == 1 ? "1 place was left out because it could not be verified."
                                              : "\(model.droppedCount) places were left out because they could not be verified.")
        }
        return out
    }
}

/// The typed lookup: the Ask Iter suggestion above your saved places and Apple Maps matches.
struct FindLookupCard: View {
    @Bindable var model: FindModel

    private var selection: Binding<String?> {
        Binding(get: { model.selectedID }, set: { model.select($0) })
    }

    var body: some View {
        VStack(spacing: 0) {
            FindCardHeader(title: "Search Results", subtitle: model.suggestions.lookup.map { "“\($0)”" }) {
                Button { model.clear() } label: { Label("Close", systemImage: "xmark") }
                    .help("Clear the search")
            }
            List(selection: selection) {
                suggestionRows
                if model.phase == .lookingUp {
                    HStack(spacing: IterSpace.sm) {
                        ProgressView().controlSize(.small)
                        Text("Searching Apple Maps…").font(IterFont.secondary).foregroundStyle(IterColor.textSecondary)
                        Spacer(minLength: 0)
                        Button("Cancel") { model.cancel() }.controlSize(.small)
                    }
                    .listRowSeparator(.hidden)
                }
                ForEach(model.matches) { match in
                    FindMatchRowView(match: match).equatable().tag(match.id)
                }
                if model.phase == .finished, model.matches.isEmpty, model.suggestions.lookup != nil {
                    Text("No matching places. Press Return to look again, or ask Iter to find spots.")
                        .font(IterFont.secondary)
                        .foregroundStyle(IterColor.textSecondary)
                        .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    @ViewBuilder private var suggestionRows: some View {
        if let ask = model.suggestions.ask {
            FindSuggestionRow(symbol: "sparkles", title: "Ask Iter: \(ask)", detail: "Find real places that fit, with a note on why",
                              showsReturn: false) { model.askIter() }
        }
        if let lookup = model.suggestions.lookup, model.phase != .lookingUp {
            FindSuggestionRow(symbol: "magnifyingglass", title: "Search Places for “\(lookup)”", detail: nil, showsReturn: true) { model.submit() }
        }
    }
}

/// A suggestion under the field: Ask Iter, or search saved places and Apple Maps (the one Return runs).
struct FindSuggestionRow: View {
    let symbol: String
    let title: String
    let detail: String?
    let showsReturn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: IterSpace.md) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(IterColor.accentText)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: IterSpace.xxs) {
                    Text(verbatim: title).font(IterFont.bodyEmphasis).foregroundStyle(IterColor.textPrimary).lineLimit(2)
                    if let detail { Text(verbatim: detail).font(IterFont.caption).foregroundStyle(IterColor.textSecondary) }
                }
                Spacer(minLength: 0)
                if showsReturn {
                    Image(systemName: "return").font(IterFont.caption).foregroundStyle(IterColor.textTertiary)
                        .help("Press Return").accessibilityHidden(true)
                }
            }
            .padding(.vertical, IterSpace.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowSeparator(.hidden)
    }
}
