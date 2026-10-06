import SwiftUI
import IterCore
import IterDesign
import IterFeatures

/// The selected day's windows in chronological order. Each row opens to its reasons (pattern #21): every factor
/// with its value, a sentence and a signed bar, the forecast age and the confidence in words.
struct DayWindowsSection: View {
    let page: SpotModel

    var body: some View {
        let light = page.dayLight
        VStack(alignment: .leading, spacing: IterSpace.md) {
            HStack(alignment: .firstTextBaseline) {
                Text(LightText.windowsTitle).font(IterFont.titleSection)
                Text(LightText.relativeDay(page.day, today: page.today) == TimeText.day(page.day)
                     ? TimeText.day(page.day)
                     : "\(LightText.relativeDay(page.day, today: page.today)) · \(TimeText.day(page.day))")
                    .font(IterFont.subheadline)
                    .foregroundStyle(IterColor.textSecondary)
                Spacer()
                if page.day != page.today {
                    Button(LightText.backToToday) { page.goToToday() }
                        .controlSize(.small)
                        .help(String(localized: "Return to today at this spot", comment: "Help"))
                }
            }
            if light.windows.isEmpty {
                Label(light.sun.kind == .polarDay ? LightText.polarDay : light.sun.kind == .polarNight ? LightText.polarNight : LightText.noWindowsPolar,
                      systemImage: light.sun.kind == .polarDay ? "sun.max" : "moon.stars")
                    .font(IterFont.callout)
                    .foregroundStyle(IterColor.textSecondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(light.windows.enumerated()), id: \.element.kind) { index, window in
                        if index > 0 { Divider() }
                        WindowRow(page: page, window: window)
                    }
                }
                .background(IterColor.backgroundControl, in: RoundedRectangle(cornerRadius: IterRadius.card, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: IterRadius.card, style: .continuous)
                    .strokeBorder(IterColor.separator, lineWidth: IterStroke.hairline))
                .clipShape(RoundedRectangle(cornerRadius: IterRadius.card, style: .continuous))
            }
        }
    }
}

private struct WindowRow: View {
    let page: SpotModel
    let window: LightWindow

    private var isExpanded: Bool { page.expanded.contains(window.kind) }
    private var isSelected: Bool { page.selectedWindow == window.kind }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { page.toggleExpanded(window.kind) } label: {
                HStack(spacing: IterSpace.sm) {
                    Image(systemName: "chevron.right")
                        .font(IterFont.captionStrong)
                        .foregroundStyle(IterColor.textSecondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: IterSize.iconSmall)
                    LightBadge(window: window, style: .regular)
                    Spacer()
                    Text(TimeText.timeRange(window.span, in: page.timeZone))
                        .font(IterFont.time)
                        .foregroundStyle(IterColor.textPrimary)
                }
                .padding(.horizontal, IterSpace.md)
                .padding(.vertical, IterSpace.sm)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(LightText.accessibilityDescription(window)), \(TimeText.timeRange(window.span, in: page.timeZone))")
            .accessibilityValue(isExpanded ? String(localized: "Expanded", comment: "VoiceOver state") : String(localized: "Collapsed", comment: "VoiceOver state"))
            .accessibilityHint(String(localized: "Shows why this window scores as it does", comment: "VoiceOver hint"))
            .help(String(localized: "Show the reasons behind this window", comment: "Help"))
            if isExpanded {
                Reasons(page: page, window: window)
                    .padding(.horizontal, IterSpace.md)
                    .padding(.bottom, IterSpace.md)
                    .padding(.leading, IterSize.iconSmall + IterSpace.sm)
            }
        }
        .background(isSelected ? IterColor.selection : .clear)
    }
}

/// The factors behind one window's score.
private struct Reasons: View {
    let page: SpotModel
    let window: LightWindow

    var body: some View {
        VStack(alignment: .leading, spacing: IterSpace.sm) {
            switch window.assessment {
            case .scored(let score):
                scored(score)
            case .noForecast(let reason):
                Text(LightText.noForecastReason(reason))
                    .font(IterFont.callout)
                    .foregroundStyle(IterColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if LightText.canRetry(reason) {
                    Button { page.retry() } label: { Label(LightText.retry, systemImage: "arrow.clockwise") }
                        .controlSize(.small)
                }
            }
        }
    }

    @ViewBuilder private func scored(_ score: LightScore) -> some View {
        Text(LightText.reasonsTitle).font(IterFont.captionStrong).foregroundStyle(IterColor.textSecondary)
        let scale = max(10, score.contributors.map { abs($0.points) }.max() ?? 10)
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: IterSpace.md, verticalSpacing: IterSpace.sm) {
            ForEach(score.contributors) { c in
                GridRow {
                    Text(LightText.title(c.factor)).font(IterFont.bodyEmphasis)
                    Text(LightText.value(c, notes: score.notes)).font(IterFont.time).foregroundStyle(IterColor.textSecondary)
                        .gridColumnAlignment(.trailing)
                    SignedBar(points: c.points, scale: scale, effect: c.effect)
                    Text(LightText.sentence(c, kind: window.kind, notes: score.notes))
                        .font(IterFont.callout)
                        .foregroundStyle(IterColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(LightText.title(c.factor)), \(LightText.value(c, notes: score.notes)), \(effectWord(c.effect)) \(LightText.points(c.points)) points. \(LightText.sentence(c, kind: window.kind, notes: score.notes))")
            }
        }
        VStack(alignment: .leading, spacing: IterSpace.xs) {
            HStack(spacing: IterSpace.sm) {
                ConfidenceMark(confidence: score.confidence)
                Text(LightText.name(score.confidence)).font(IterFont.subheadline)
                if let range = LightText.range(score) {
                    Text(verbatim: "·").foregroundStyle(IterColor.textSecondary)
                    Text("Likely \(range)", comment: "Score range for days further out").font(IterFont.subheadline)
                }
                Text(verbatim: "·").foregroundStyle(IterColor.textSecondary)
                Text(LightText.sourceUpdated(score.source, model: score.model, fetchedAt: score.forecastFetchedAt,
                                             fallbackFrom: page.forecast?.source == score.source ? page.forecast?.fallbackFrom ?? [] : []))
                    .font(IterFont.subheadline).foregroundStyle(IterColor.textSecondary)
            }
            Text("\(LightText.confidenceExplained(score.confidence)) \(LightText.leadNote(hours: score.leadHours))")
                .font(IterFont.footnote)
                .foregroundStyle(IterColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(score.notes, id: \.self) { note in
                Text(LightText.note(note, source: score.source))
                    .font(IterFont.footnote)
                    .foregroundStyle(IterColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        ExplainBlock(page: page, window: window)
    }

    private func effectWord(_ e: LightContributor.Effect) -> String {
        switch e {
        case .helps: LightText.helps
        case .hurts: LightText.hurts
        case .neutral: LightText.neutral
        }
    }
}

/// A small centred bar: right of the line helps, left hurts. The sign is also printed, so colour is never the only cue.
private struct SignedBar: View {
    let points: Int
    let scale: Int
    let effect: LightContributor.Effect

    private static let half = IterSize.lightRingLarge / 2 + IterSpace.xs

    var body: some View {
        let length = Self.half * CGFloat(min(1, Double(abs(points)) / Double(scale)))
        HStack(spacing: IterSpace.xs) {
            ZStack {
                Rectangle().fill(IterColor.separator).frame(width: IterStroke.thin, height: IterSize.iconSmall)
                RoundedRectangle(cornerRadius: IterStroke.thin)
                    .fill(IterColor.textSecondary) // direction shows helps or hurts; colour must not read as good or bad
                    .frame(width: max(length, points == 0 ? 0 : IterStroke.thick), height: IterSpace.sm)
                    .offset(x: points >= 0 ? max(length, 0) / 2 : -max(length, 0) / 2)
            }
            .frame(width: Self.half * 2)
            Text(LightText.points(points))
                .font(IterFont.timeSmall)
                .foregroundStyle(IterColor.textSecondary)
                .frame(width: IterSize.badgeMinWidth, alignment: .leading)
        }
        .accessibilityHidden(true)
    }
}

/// "Explain": Apple Intelligence writes a plain-language reading of the factors. Absent when it is unavailable.
private struct ExplainBlock: View {
    let page: SpotModel
    let window: LightWindow

    private var isSelected: Bool { page.selectedWindow == window.kind }

    var body: some View {
        if page.explainerAvailable {
            VStack(alignment: .leading, spacing: IterSpace.sm) {
                switch isSelected ? page.explanation : .idle {
                case .idle:
                    button(LightText.explain)
                case .loading:
                    HStack(spacing: IterSpace.sm) {
                        ProgressView().controlSize(.small)
                        Text(LightText.explaining).font(IterFont.callout).foregroundStyle(IterColor.textSecondary)
                        Button(LightText.cancel) { page.cancelExplanation() }.controlSize(.small)
                    }
                case .done(let text):
                    Text(text).font(IterFont.callout).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    HStack(spacing: IterSpace.sm) {
                        Label(LightText.writtenByAppleIntelligence, systemImage: "apple.intelligence")
                            .font(IterFont.caption)
                            .foregroundStyle(IterColor.textSecondary)
                        button(LightText.explainAgain)
                    }
                case .failed(let failure):
                    Text(LightText.explanationFailure(failure)).font(IterFont.callout).foregroundStyle(IterColor.textSecondary)
                    button(LightText.explain)
                }
            }
        }
    }

    private func button(_ title: String) -> some View {
        Button {
            page.selectWindow(window.kind)
            page.explain(intentName: LightText.name(page.intent))
        } label: {
            Label(title, systemImage: "apple.intelligence")
        }
        .controlSize(.small)
        .help(String(localized: "Write a plain-language explanation with Apple Intelligence", comment: "Help"))
    }
}
