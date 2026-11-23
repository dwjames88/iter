import SwiftUI
import IterFeatures
import IterModel
import IterSky
import IterUI

// Modules 1 to 3: when to go, the 10-day outlook, and the light windows of the selected day.

struct WhenToGoModule: View {
    let model: ConditionsModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ModuleCard(title: "When to Go", symbol: "calendar.badge.clock") {
            if let best = model.whenToGo {
                let zone = model.place.timeZone
                let start = model.windows.first { $0.kind == best.kind && best.day == model.selectedDay }?.span.start ?? best.day.start(in: zone)
                HStack(alignment: .top, spacing: IterGrid.laneGap) {
                    VStack(alignment: .leading, spacing: IterSpace.xs) {
                        Text(verbatim: TimeText.longDay(best.day))
                            .font(IterFont.scoreLarge)
                            .foregroundStyle(IterColor.textPrimary)
                        HStack(spacing: IterSpace.xs) {
                            WindowSymbol(kind: best.kind, font: .system(size: 13))
                            Text(verbatim: ConditionsText.name(best.kind)).font(IterFont.headline).foregroundStyle(IterColor.textPrimary)
                        }
                        Text(verbatim: ConditionsFormat.whenToGoReason(best, windows: model.windows, selectedDay: model.selectedDay))
                            .font(IterFont.body).foregroundStyle(IterColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    ScoreChip(kind: best.kind, start: start, score: best.score, zone: zone, size: .small, timeStyle: .none,
                              isLowConfidence: best.confidence == .low)
                        .id("\(best.day.iso)-\(best.kind.rawValue)-\(best.score)")
                        .transition(.opacity)
                }
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: best.score)
                if best.isProvisional {
                    Label("Provisional: more days are still loading", systemImage: "hourglass")
                        .font(IterFont.secondary).foregroundStyle(IterColor.textSecondary)
                }
                if best.day != model.selectedDay {
                    Button("Show This Day") { model.select(day: best.day) }
                        .controlSize(.small)
                }
            } else if model.outlook.contains(where: { $0.load == .loading }) {
                VStack(alignment: .leading, spacing: IterSpace.xs) {
                    SkeletonBar(width: 180, height: 22)
                    SkeletonBar(width: 120)
                    SkeletonBar()
                }
            } else {
                Text("No scored window in the coming days.").font(IterFont.body).foregroundStyle(IterColor.textSecondary)
            }
        }
    }
}

struct OutlookModule: View {
    let model: ConditionsModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ModuleCard(title: "10-Day Outlook", symbol: "calendar") {
            VStack(spacing: 0) {
                ForEach(Array(model.outlook.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { Divider().padding(.leading, IterGrid.laneGap) }
                    OutlookRowView(row: row, zone: model.place.timeZone, fallbackKind: model.place.defaultSession) {
                        model.select(day: row.day)
                    }
                }
                if model.outlook.isEmpty {
                    SkeletonBar().padding(.vertical, IterSpace.sm)
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: model.outlook)
        }
    }
}

struct OutlookRowView: View {
    let row: OutlookRow
    let zone: TimeZone
    let fallbackKind: LightWindowKind
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: IterGrid.laneGap) {
                VStack(alignment: .leading, spacing: IterSpace.xxs) {
                    Text(verbatim: row.isToday ? "Today" : TimeText.day(row.day))
                        .font(IterFont.headline).foregroundStyle(IterColor.textPrimary)
                    Text(verbatim: subtitle).font(IterFont.secondary).foregroundStyle(IterColor.textSecondary)
                }
                Spacer(minLength: 0)
                ScoreChip(kind: row.bestKind ?? fallbackKind, start: row.day.start(in: zone), score: row.score, zone: zone, size: .compact,
                          timeStyle: .none, isLowConfidence: row.confidence == .low, isLoading: row.load == .loading)
            }
            .padding(.horizontal, IterSpace.xs)
            .frame(minHeight: IterGrid.rowDouble)
            .opacity(row.opacity)
            .background(row.isSelected ? IterColor.selection : .clear, in: RoundedRectangle(cornerRadius: IterRadius.control, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(row.isToday ? "Today" : TimeText.day(row.day)), \(subtitle)\(row.score.map { ", score \($0)" } ?? "")"))
        .accessibilityAddTraits(row.isSelected ? [.isButton, .isSelected] : .isButton)
    }

    var subtitle: String {
        switch row.load {
        case .loading: "Loading"
        case .unavailable: "No forecast"
        case .ready:
            [row.bestKind.map(ConditionsText.name), row.band.map(ConditionsText.name), row.confidence == .low ? "Low confidence" : nil]
                .compactMap { $0 }.joined(separator: " \u{00B7} ")
        }
    }
}

struct WindowsModule: View {
    let model: ConditionsModel
    @State private var expanded: Set<LightWindowKind> = []

    var body: some View {
        ModuleCard(title: "Light Windows", symbol: "sun.horizon") {
            let zone = model.place.timeZone
            if model.windows.isEmpty {
                if model.status == .loading {
                    VStack(spacing: IterSpace.sm) { ForEach(0..<3, id: \.self) { _ in SkeletonBar(height: 28) } }
                } else {
                    Text("No light windows for this day.").font(IterFont.body).foregroundStyle(IterColor.textSecondary)
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(model.windows.sorted { $0.span.start < $1.span.start }.enumerated()), id: \.element.id) { index, w in
                        if index > 0 { Divider().padding(.leading, IterGrid.disclosureLane + IterGrid.laneGap) }
                        WindowRowView(window: w, zone: zone, isExpanded: expanded.contains(w.kind), isLoading: model.status == .loading) {
                            if expanded.contains(w.kind) { expanded.remove(w.kind) } else { expanded.insert(w.kind) }
                        }
                    }
                }
            }
        }
    }
}

struct WindowRowView: View {
    let window: WindowDetail
    let zone: TimeZone
    let isExpanded: Bool
    let isLoading: Bool
    let toggle: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: IterSpace.sm) {
            Button(action: toggle) {
                HStack(alignment: .center, spacing: IterGrid.laneGap) {
                    Image(systemName: "chevron.right")
                        .font(IterFont.secondary.weight(.semibold))
                        .foregroundStyle(IterColor.textSecondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: IterGrid.disclosureLane)
                        .accessibilityHidden(true)
                    WindowSymbol(kind: window.kind, font: .system(size: 14))
                        .frame(width: IterSize.iconMedium)
                    VStack(alignment: .leading, spacing: IterSpace.xxs) {
                        Text(verbatim: ConditionsText.name(window.kind)).font(IterFont.headline).foregroundStyle(IterColor.textPrimary)
                        Text(verbatim: TimeText.timeRange(window.effectiveSpan ?? window.span, in: zone))
                            .font(IterFont.time).foregroundStyle(IterColor.textSecondary)
                    }
                    Spacer(minLength: 0)
                    ScoreChip(kind: window.kind, start: window.span.start, end: window.effectiveEnd, score: window.score, zone: zone, size: .small,
                              timeStyle: .none, isLowConfidence: window.confidence == .low, isLoading: isLoading && window.score == nil)
                }
                .frame(minHeight: IterGrid.rowDouble)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isButton)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")

            if isExpanded {
                WindowReasons(window: window, zone: zone)
                    .padding(.leading, IterGrid.disclosureLane + IterGrid.laneGap)
                    .transition(reduceMotion ? .identity : .opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: isExpanded)
    }
}

/// Why the score is what it is: confidence, per-factor reasons, causes in plain words, notes and flags.
struct WindowReasons: View {
    let window: WindowDetail
    let zone: TimeZone

    var body: some View {
        VStack(alignment: .leading, spacing: IterSpace.sm) {
            if let u = window.unavailable {
                Text(verbatim: ConditionsText.phrase(u)).font(IterFont.body).foregroundStyle(IterColor.textSecondary)
            } else {
                HStack(spacing: IterSpace.sm) {
                    if let c = window.confidence { ConfidenceIndicator(ConditionsFormat.confidenceLevel(c)) }
                    if let likely = ConditionsFormat.likely(window.range) {
                        Text(verbatim: likely).font(IterFont.secondary).foregroundStyle(IterColor.textSecondary)
                    }
                    if window.isStale { Text("Stale forecast").font(IterFont.secondary).foregroundStyle(IterColor.warning) }
                }
                if !window.contributors.isEmpty {
                    let scale = Double(max(10, window.contributors.map { abs($0.points) }.max() ?? 10))
                    VStack(spacing: 0) {
                        ForEach(Array(window.contributors.enumerated()), id: \.offset) { _, c in
                            let f = ConditionsFormat.factor(c)
                            FactorRow(name: f.name, symbol: f.symbol, valueText: f.value, contribution: .points(c.points), scaleMax: scale)
                        }
                    }
                }
                if !window.causes.isEmpty {
                    VStack(alignment: .leading, spacing: IterSpace.xs) {
                        Text("Why the confidence is not higher").font(IterFont.secondary.weight(.semibold)).foregroundStyle(IterColor.textSecondary)
                        ForEach(Array(window.causes.enumerated()), id: \.offset) { _, cause in
                            Text(verbatim: ConditionsText.phrase(cause)).font(IterFont.body).foregroundStyle(IterColor.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            ForEach(Array(window.notes.enumerated()), id: \.offset) { _, n in
                Text(verbatim: ConditionsFormat.noteText(n)).font(IterFont.secondary).foregroundStyle(IterColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(Array(window.flags.enumerated()), id: \.offset) { _, f in
                Label(ConditionsFormat.flagText(f, zone: zone), systemImage: "info.circle")
                    .font(IterFont.secondary).foregroundStyle(IterColor.textSecondary)
            }
        }
        .padding(.bottom, IterSpace.sm)
    }
}
