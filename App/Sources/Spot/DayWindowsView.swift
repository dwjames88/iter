import SwiftUI
import IterCore
import IterDesign
import IterFeatures

/// The lane widths shared by every window row, measured once.
@MainActor enum WindowLanes {
    static let unit = EventScore.unitWidth(.regular, timeStyle: .range)
    /// How far windows inside an open day are indented: one disclosure lane and its gap.
    static let nestedIndent = IterGrid.disclosureLane + IterGrid.laneGap
    /// Where the label lane starts: inset, disclosure lane, lane gap. Dividers and reasons indent to it.
    static let labelStart = IterGrid.inset + IterGrid.disclosureLane + IterGrid.laneGap
}

/// One outlook day's windows in chronological order, shown inside the day when it is open (OutlookStrip). On today
/// only the windows still ahead; a day with none says so in one secondary line. Each row opens to its reasons
/// (pattern #21): every factor with its value, a sentence and a signed bar, the forecast age and the confidence in
/// words, and on the full page the Explain block.
/// Rows sit on fixed lanes: disclosure, label, and the event unit (symbol, score and time range), which is the whole rating; VoiceOver still hears band and confidence (HIERARCHY.md).
struct DayWindowsList: View {
    let page: SpotModel
    let day: LocalDay

    var body: some View {
        let light = page.dayLight(on: day)
        let rows = windows(light)
        if rows.isEmpty {
            Text(emptyLine(light))
                .font(IterFont.secondary)
                .foregroundStyle(IterColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, WindowLanes.labelStart)
                .padding(.trailing, IterGrid.inset)
                .padding(.vertical, IterSpace.sm)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, window in
                    // No divider under the day row; between windows it starts at the nested label lane.
                    if index > 0 { Divider().padding(.leading, WindowLanes.labelStart + WindowLanes.nestedIndent) }
                    WindowRow(page: page, window: window, day: day)
                }
            }
            // Nested one disclosure lane: a window's chevron sits under the day's label, so it reads as part of the day.
            .padding(.leading, WindowLanes.nestedIndent)
            .layoutGrid(lanes: LayoutLane.standardRowLanes(disclosure: true, event: .regular, time: .range))
        }
    }

    /// Today: the windows that have not ended; any other day: all of them.
    private func windows(_ light: DayLight) -> [LightWindow] {
        if day == page.today { return page.upcomingWindows.filter { $0.day == day }.map(\.window) }
        return light.windows
    }

    private func emptyLine(_ light: DayLight) -> String {
        switch light.sun.kind {
        case .polarDay: LightText.polarDay
        case .polarNight: LightText.polarNight
        case .normal: day == page.today ? LightText.nothingLeftToday : LightText.noWindowsPolar
        }
    }
}

struct WindowRow: View {
    let page: SpotModel
    let window: LightWindow
    let day: LocalDay

    @Environment(\.spotDensity) private var density
    /// A row from another day (tomorrow's, listed under today's) opens that day instead of expanding in place.
    private var isOtherDay: Bool { day != page.day }
    private var isScored: Bool { window.assessment.lightScore != nil }
    private var isExpandable: Bool { isScored && !isOtherDay }
    private var isExpanded: Bool { isExpandable && page.expanded.contains(window.kind) }
    private var isSelected: Bool { !isOtherDay && page.selectedWindow == window.kind }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if isOtherDay { page.selectDay(day) } else if isExpandable { page.toggleExpanded(window.kind) }
            } label: {
                HStack(alignment: .center, spacing: IterGrid.laneGap) {
                    // Disclosure lane: kept on rows that cannot expand, so the label lane starts at one x.
                    Image(systemName: "chevron.right")
                        .font(IterFont.moduleTitle)
                        .foregroundStyle(IterColor.textSecondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: IterGrid.disclosureLane)
                        .opacity(isExpandable ? 1 : 0)
                        .accessibilityHidden(true)
                    // Label lane (flexible): the window's name; the narrow place card uses the short name ("Blue PM"),
                    // as the timeline does, so the lane never truncates. The full name stays in VoiceOver.
                    Text(density == .page ? LightText.name(window.kind) : LightText.shortName(window.kind))
                        .font(IterFont.headline)
                        .foregroundStyle(IterColor.textPrimary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    EventScore(window: window, zone: page.timeZone, timeStyle: .range, variant: .regular,
                               isLoading: page.isLoadingForecast)
                }
                .padding(.horizontal, IterGrid.inset)
                .padding(.vertical, IterSpace.sm)
                .frame(minHeight: IterGrid.rowSingle)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(LightText.accessibilityDescription(window)), \(TimeText.timeRange(window.span, in: page.timeZone))")
            .accessibilityValue(isExpanded ? String(localized: "Expanded", comment: "VoiceOver state") : String(localized: "Collapsed", comment: "VoiceOver state"))
            .accessibilityHint(isOtherDay ? String(localized: "Opens this day", comment: "VoiceOver hint")
                               : String(localized: "Shows why this window scores as it does", comment: "VoiceOver hint"))
            .help(isOtherDay ? String(localized: "Open this day", comment: "Help")
                  : String(localized: "Show the reasons behind this window", comment: "Help"))
            if isExpanded {
                Reasons(page: page, window: window)
                    .padding(.leading, WindowLanes.labelStart)
                    .padding(.trailing, IterGrid.inset)
                    .padding(.bottom, IterGrid.inset)
            }
        }
        .background(isSelected ? IterColor.selection : .clear)
    }
}

/// The factors behind one window's score.
private struct Reasons: View {
    let page: SpotModel
    let window: LightWindow
    @Environment(\.spotDensity) private var density

    var body: some View {
        VStack(alignment: .leading, spacing: IterSpace.sm) {
            switch window.assessment {
            case .scored(let score):
                scored(score)
            case .noForecast:
                EmptyView()
            }
        }
    }

    @ViewBuilder private func scored(_ score: LightScore) -> some View {
        Text(LightText.reasonsTitle).font(IterFont.moduleTitle).foregroundStyle(IterColor.textSecondary)
        let scale = max(10, score.contributors.map { abs($0.points) }.max() ?? 10)
        if density == .panel {
            VStack(alignment: .leading, spacing: IterSpace.sm) {
                ForEach(score.contributors) { c in
                    VStack(alignment: .leading, spacing: IterSpace.xs) {
                        HStack(alignment: .firstTextBaseline, spacing: IterSpace.sm) {
                            Text(LightText.title(c.factor)).font(IterFont.headline)
                            Text(LightText.value(c, notes: score.notes)).font(IterFont.time).foregroundStyle(IterColor.textSecondary)
                            Spacer(minLength: 0)
                            SignedBar(points: c.points, scale: scale, effect: c.effect)
                        }
                        Text(LightText.sentence(c, kind: window.kind, notes: score.notes))
                            .font(IterFont.body)
                            .foregroundStyle(IterColor.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(LightText.title(c.factor)), \(LightText.value(c, notes: score.notes)), \(effectWord(c.effect)) \(LightText.points(c.points)) points. \(LightText.sentence(c, kind: window.kind, notes: score.notes))")
                }
            }
        } else {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: IterSpace.lg, verticalSpacing: IterSpace.sm) {
                ForEach(score.contributors) { c in
                    GridRow {
                        Text(LightText.title(c.factor)).font(IterFont.headline)
                        Text(LightText.value(c, notes: score.notes)).font(IterFont.time).foregroundStyle(IterColor.textSecondary)
                            .gridColumnAlignment(.trailing)
                        SignedBar(points: c.points, scale: scale, effect: c.effect)
                        Text(LightText.sentence(c, kind: window.kind, notes: score.notes))
                            .font(IterFont.body)
                            .foregroundStyle(IterColor.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(LightText.title(c.factor)), \(LightText.value(c, notes: score.notes)), \(effectWord(c.effect)) \(LightText.points(c.points)) points. \(LightText.sentence(c, kind: window.kind, notes: score.notes))")
                }
            }
        }
        VStack(alignment: .leading, spacing: IterSpace.xs) {
            if density == .panel {
                VStack(alignment: .leading, spacing: IterSpace.xs) {
                    HStack(spacing: IterSpace.sm) {
                        ConfidenceMark(confidence: score.confidence)
                        Text(LightText.name(score.confidence)).font(IterFont.secondary)
                        if let range = LightText.range(score) {
                            Text(verbatim: "·").foregroundStyle(IterColor.textSecondary)
                            Text("Likely \(range)", comment: "Score range for days further out").font(IterFont.secondary)
                        }
                    }
                    Text(LightText.sourceUpdated(score.source, model: score.model, fetchedAt: score.forecastFetchedAt,
                                                 fallbackFrom: page.forecast?.source == score.source ? page.forecast?.fallbackFrom ?? [] : []))
                        .font(IterFont.secondary).foregroundStyle(IterColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                HStack(spacing: IterSpace.sm) {
                    ConfidenceMark(confidence: score.confidence)
                    Text(LightText.name(score.confidence)).font(IterFont.secondary)
                    if let range = LightText.range(score) {
                        Text(verbatim: "·").foregroundStyle(IterColor.textSecondary)
                        Text("Likely \(range)", comment: "Score range for days further out").font(IterFont.secondary)
                    }
                    Text(verbatim: "·").foregroundStyle(IterColor.textSecondary)
                    Text(LightText.sourceUpdated(score.source, model: score.model, fetchedAt: score.forecastFetchedAt,
                                                 fallbackFrom: page.forecast?.source == score.source ? page.forecast?.fallbackFrom ?? [] : []))
                        .font(IterFont.secondary).foregroundStyle(IterColor.textSecondary)
                }
            }
            Text("\(LightText.confidenceExplained(score.confidence)) \(LightText.leadNote(hours: score.leadHours))")
                .font(IterFont.secondary)
                .foregroundStyle(IterColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(score.notes, id: \.self) { note in
                Text(LightText.note(note, source: score.source))
                    .font(IterFont.secondary)
                    .foregroundStyle(IterColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        if density == .page { ExplainBlock(page: page, window: window) }
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
                        Text(LightText.explaining).font(IterFont.body).foregroundStyle(IterColor.textSecondary)
                        Button(LightText.cancel) { page.cancelExplanation() }.controlSize(.small)
                    }
                case .done(let text):
                    Text(text).font(IterFont.body).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    HStack(spacing: IterSpace.sm) {
                        Label(LightText.writtenByAppleIntelligence, systemImage: "apple.intelligence")
                            .font(IterFont.secondary)
                            .foregroundStyle(IterColor.textSecondary)
                        button(LightText.explainAgain)
                    }
                case .failed(let failure):
                    Text(LightText.explanationFailure(failure)).font(IterFont.body).foregroundStyle(IterColor.textSecondary)
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
