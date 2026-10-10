import SwiftUI
import IterCore
import IterDesign
import IterFeatures

/// The Search Here slot at the top of the Explore list, on the Mac card, the iPhone sheet and the iPad column. One of
/// three things, never a fake count: the "Search Here" button (a system glass capsule) when the list no longer
/// describes the map, a compact progress line with Cancel while it runs, and, after it ran and found nothing, a quiet
/// line saying so and which source could not answer. The sections' own headers carry the counts and the sources.
struct SearchHereControl: View {
    @Bindable var explore: ExploreModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Mode: Equatable { case progress, button, none }

    private var mode: Mode {
        if explore.searchHereStatus.isSearching { return .progress }
        return explore.showsSearchHere ? .button : .none
    }

    /// Lines about an empty or failed Search Here that no section header can carry: the run is over, found nothing, and
    /// the map still shows what it searched.
    private var notes: [String] {
        let status = explore.searchHereStatus
        guard status.phase == .finished, status.total == 0,
              !SearchHereRules.isStale(listRegion: status.region, visible: explore.visibleRegion) else { return [] }
        return LightText.inViewNotes(status)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: IterSpace.xs) {
            switch mode {
            case .progress: progress.transition(.opacity)
            case .button: button.transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .leading)))
            case .none: EmptyView()
            }
            if mode != .progress, !notes.isEmpty {
                VStack(alignment: .leading, spacing: IterSpace.xxs) {
                    ForEach(notes, id: \.self) { Text($0) }
                }
                .font(IterFont.caption)
                .foregroundStyle(IterColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: mode)
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: notes)
    }

    private var button: some View {
        GlassEffectContainer {
            Button { explore.searchHere() } label: {
                Label(LightText.searchHere, systemImage: "magnifyingglass")
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            #if os(iOS)
            .controlSize(.large)
            #endif
            .help(LightText.searchHereHelp)
            .accessibilityHint(LightText.searchHereHelp)
        }
    }

    private var progress: some View {
        HStack(spacing: IterSpace.sm) {
            ProgressView().controlSize(.small)
            Text(LightText.searchHereProgress(explore.searchHereStatus))
                .font(IterFont.caption)
                .foregroundStyle(IterColor.textSecondary)
            Spacer(minLength: 0)
            Button { explore.cancelSearchHere() } label: { Text(LightText.searchHereCancel) }
                .controlSize(.small)
                #if os(iOS)
                .frame(minHeight: 44)
                #endif
                .help(LightText.searchHereCancelHelp)
                .accessibilityHint(LightText.searchHereCancelHelp)
        }
        .accessibilityElement(children: .contain)
    }
}

/// A section header that names what it holds and where it came from: "12 Places in View · Maps + Ask", then a quiet
/// line for anything that could not answer ("Reddit unavailable"). Used by the In View and feature sections.
struct ResultSectionHeader: View {
    let title: String
    let sources: [String]
    let notes: [String]
    var titleFont: Font
    var detailFont: Font = IterFont.caption

    private var headline: AttributedString {
        var head = AttributedString(title)
        head.font = titleFont
        guard !sources.isEmpty else { return head }
        var tail = AttributedString(" · " + LightText.sourceSummary(sources))
        tail.font = detailFont
        return head + tail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: IterSpace.xxs) {
            Text(headline)
            ForEach(notes, id: \.self) { note in
                Text(note).font(detailFont)
            }
        }
        .foregroundStyle(IterColor.textSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

extension ExploreModel {
    /// The header of the In View or feature section, as plain values, or nil for every other section.
    func resultHeader(for section: ExploreSection) -> (title: String, sources: [String], notes: [String])? {
        switch section.kind {
        case .inView:
            let status = searchHereStatus
            return (LightText.inViewTitle(count: section.rows.count), LightText.inViewSources(status), LightText.inViewNotes(status))
        case .feature:
            let status = featureStatus
            var notes = LightText.featureNotes(status)
            if status.isSearching {
                notes.insert(LightText.searchProgress(status, area: LightText.featureAreaName(self)), at: 0)
            }
            let title = LightText.featureTitle(count: section.rows.count, feature: status.feature,
                                               area: LightText.featureAreaName(self))
            return (title, LightText.featureSources(status), notes)
        default:
            return nil
        }
    }
}

/// One row of the In View or feature section: the normal row with its sources and height, or, for a place Ask
/// suggested, the Ask row (the scout's note under it).
struct ExploreResultRow: View {
    let row: ExploreRow
    var showsDistance = false

    var body: some View {
        if row.viaAsk {
            ExploreAskRow(row: row, showsDistance: showsDistance, showsSources: true)
        } else {
            ExploreRowView(row: row, showsDistance: showsDistance, showsSources: true).equatable()
        }
    }
}
