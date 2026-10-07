import SwiftUI
import IterCore
import IterDesign
import IterFeatures
import IterServices

/// The search field's suggestions at the top of the list: an "Apple Maps" group and an "Ask Iter" group, ranked by
/// what the text reads like (`SearchSuggestions`). Return runs the first row; every row is a button. An Ask the device
/// cannot run stays, quiet and disabled, with the reason.
struct ExploreSuggestionsView: View {
    let suggestions: [SearchSuggestion]
    let action: (SearchSuggestion) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: IterSpace.sm) {
            ForEach(suggestions) { suggestion in
                VStack(alignment: .leading, spacing: IterSpace.xs) {
                    Text(LightText.suggestionGroup(suggestion))
                        .font(IterFont.moduleTitle)
                        .foregroundStyle(IterColor.textSecondary)
                        .accessibilityAddTraits(.isHeader)
                    ExploreSuggestionRow(suggestion: suggestion, runsOnReturn: suggestion.id == suggestions.first?.id) { action(suggestion) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, IterSpace.xs)
    }
}

struct ExploreSuggestionRow: View {
    let suggestion: SearchSuggestion
    /// The top suggestion: the one Return runs.
    var runsOnReturn = false
    let action: () -> Void

    private var symbol: String {
        if case .ask = suggestion.kind { "sparkles" } else { "magnifyingglass" }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: IterSpace.md) {
                Image(systemName: symbol)
                    .foregroundStyle(suggestion.isAvailable ? AnyShapeStyle(IterColor.accent) : AnyShapeStyle(IterColor.textSecondary))
                    .frame(width: IterSize.iconSmall)
                VStack(alignment: .leading, spacing: IterSpace.xxs) {
                    Text(LightText.suggestionTitle(suggestion))
                        .font(IterFont.bodyEmphasis)
                        .foregroundStyle(suggestion.isAvailable ? AnyShapeStyle(IterColor.textPrimary) : AnyShapeStyle(IterColor.textSecondary))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if let detail = LightText.suggestionDetail(suggestion) {
                        Text(detail)
                            .font(IterFont.caption)
                            .foregroundStyle(IterColor.textSecondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
                if runsOnReturn && suggestion.isAvailable {
                    Image(systemName: "return")
                        .font(IterFont.caption)
                        .foregroundStyle(IterColor.textSecondary)
                        .help(String(localized: "Press Return", comment: "Tooltip on the top search suggestion"))
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, IterSpace.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!suggestion.isAvailable)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(LightText.suggestionAccessibility(suggestion))
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(runsOnReturn && suggestion.isAvailable
            ? Text("Runs when you press Return", comment: "VoiceOver hint on the top search suggestion") : Text(verbatim: ""))
    }
}

/// The Ask section: header with the submitted request, then the running stages with Cancel, or the failure with its
/// honest message and "Search Apple Maps Instead", or the suggested places (each the normal row plus the scout's note).
/// Drawn inside the list, first.
struct ExploreAskSection: View {
    @Bindable var explore: ExploreModel
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL

    private static let systemSettingsURL = URL(string: "x-apple.systempreferences:com.apple.Siri-Settings.extension")

    private var results: [ExploreRow] {
        explore.sections.first { $0.kind == .ask }?.rows ?? []
    }

    var body: some View {
        Section {
            switch explore.askState {
            case .idle:
                EmptyView()
            case .running(let stage, let started):
                running(stage: stage, started: started)
            case .failed(let failure):
                failed(failure)
            case .results:
                ForEach(results) { row in
                    ExploreAskRow(row: row, isHovered: explore.hoveredID == row.id, showsDistance: explore.hasLocation)
                        .id(row.id)
                        .tag(row.id)
                        .onAppear { explore.requestForecast(for: row.id) }
                        .onHover { inside in
                            if inside { explore.hoveredID = row.id } else if explore.hoveredID == row.id { explore.hoveredID = nil }
                        }
                }
                Text(LightText.askSourceLine)
                    .font(IterFont.caption)
                    .foregroundStyle(IterColor.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            header
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: IterSpace.xxs) {
            HStack {
                Label(LightText.name(.ask), systemImage: "sparkles")
                Spacer()
                if case .results = explore.askState { Text(results.count, format: .number).monospacedDigit() }
            }
            .font(IterFont.captionStrong)
            Text(LightText.askRequest(explore.askSubmittedRequest))
                .font(IterFont.caption)
                .lineLimit(2)
        }
        .foregroundStyle(IterColor.textSecondary)
        .accessibilityElement(children: .combine)
    }

    // MARK: Running

    private func running(stage: ScoutProgress, started: Date) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let _ = context.date
            let elapsed = model.now().timeIntervalSince(started)
            HStack(alignment: .center, spacing: IterSpace.sm) {
                ProgressView().controlSize(.small)
                VStack(alignment: .leading, spacing: IterSpace.xxs) {
                    Text(LightText.askStage(stage))
                        .font(IterFont.bodyEmphasis)
                    HStack(spacing: IterSpace.xs) {
                        Text(LightText.askStep(stage))
                        Text("·")
                        Text(LightText.askElapsed(elapsed)).monospacedDigit()
                    }
                    .font(IterFont.caption)
                    .foregroundStyle(IterColor.textSecondary)
                    if elapsed >= Self.slowAfter {
                        Text(LightText.askSlow)
                            .font(IterFont.caption)
                            .foregroundStyle(IterColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                Button { explore.cancelAsk() } label: { Text(LightText.askCancel) }
                    .controlSize(.small)
                    .help(LightText.askCancelHelp)
                    .accessibilityLabel(LightText.askCancel)
                    .accessibilityHint(LightText.askCancelHelp)
            }
            .padding(.vertical, IterSpace.xs)
        }
    }

    private static let slowAfter: TimeInterval = 10

    // MARK: Failure

    private func failed(_ failure: ScoutFailure) -> some View {
        let notice = LightText.askFailure(failure)
        var retryable = true
        var needsSettings = false
        if case .unavailable(let availability) = failure {
            retryable = false
            needsSettings = availability == .appleIntelligenceNotEnabled
        }
        return VStack(alignment: .leading, spacing: IterSpace.sm) {
            Label(notice.title, systemImage: notice.symbol)
                .font(IterFont.bodyEmphasis)
            Text(notice.detail)
                .font(IterFont.caption)
                .foregroundStyle(IterColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: IterSpace.sm) {
                Button { explore.searchAppleMapsInstead() } label: { Text(LightText.askSearchInstead) }
                    .buttonStyle(.borderedProminent)
                if retryable {
                    Button { explore.ask() } label: { Text(LightText.askTryAgain) }
                }
                if needsSettings, let url = Self.systemSettingsURL {
                    Button { openURL(url) } label: { Text(LightText.askOpenSystemSettings) }
                }
            }
            .controlSize(.small)
        }
        .padding(.vertical, IterSpace.xs)
        .accessibilityElement(children: .contain)
    }
}

/// One suggested place: the normal Explore row, then the note Apple Intelligence wrote for it (and the drive time when
/// the scout checked one).
struct ExploreAskRow: View {
    let row: ExploreRow
    var isHovered = false
    var showsDistance = false

    var body: some View {
        VStack(alignment: .leading, spacing: IterSpace.xxs) {
            ExploreRowView(row: row, isHovered: isHovered, showsDistance: showsDistance)
            if let seconds = row.driveSeconds {
                Label(LightText.askDrive(seconds), systemImage: "car")
                    .font(IterFont.caption)
                    .foregroundStyle(IterColor.textSecondary)
            }
            if let note = row.note {
                HStack(alignment: .firstTextBaseline, spacing: IterSpace.xs) {
                    Image(systemName: "sparkles").imageScale(.small)
                    Text(note)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(IterFont.callout)
                .foregroundStyle(IterColor.textSecondary)
                .help(LightText.askNoteLabel)
            }
        }
        .padding(.bottom, IterSpace.xs)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(LightText.askRowAccessibility(row, showsDistance: showsDistance))
    }
}
