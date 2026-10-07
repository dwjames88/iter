import SwiftUI
import IterCore
import IterDesign
import IterFeatures
import IterServices

/// The "Ask Iter…" row at the top of the list: offered whenever the field has text and no ask is running or shown for it.
struct ExploreAskOfferRow: View {
    let query: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: IterSpace.md) {
                Image(systemName: "sparkles")
                    .foregroundStyle(IterColor.accent)
                    .frame(width: IterSize.iconSmall)
                VStack(alignment: .leading, spacing: IterSpace.xxs) {
                    Text(LightText.askOffer(query))
                        .font(IterFont.bodyEmphasis)
                        .foregroundStyle(IterColor.textPrimary)
                        .lineLimit(2)
                    Text(LightText.askOfferDetail)
                        .font(IterFont.caption)
                        .foregroundStyle(IterColor.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, IterSpace.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(LightText.askOfferAccessibility(query))
        .accessibilityAddTraits(.isButton)
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
