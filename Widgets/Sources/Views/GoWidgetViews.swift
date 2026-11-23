import IterGoActivity
import IterModel
import IterUI
import SwiftUI
import WidgetKit

/// The `IterGoNext` widget families, as plain values so the views render in tests without WidgetKit's `WidgetFamily`.
enum GoWidgetFamily: Hashable, Sendable {
    case small, medium, accessoryRectangular, accessoryCircular, accessoryInline
}

/// One view for every `IterGoNext` family, drawn from the snapshot in the App Group. The extension adds the container
/// background and the URL; the system draws the accessory backgrounds. Every family shows the snapshot's age once it is old.
struct GoWidgetView: View {
    let snapshot: GoSnapshot
    let clock: GoClock
    let family: GoWidgetFamily
    var isStale = false

    private var zone: TimeZone {
        (snapshot.next ?? snapshot.current).flatMap { TimeZone(identifier: $0.timeZoneIdentifier) } ?? .current
    }

    private var p: GoPresentation { GoPresentation(GoActivityContent(snapshot: snapshot), clock: clock, zone: zone, isStale: isStale) }

    var body: some View {
        let p = p
        Group {
            switch family {
            case .small: GoSmallWidget(p: p, snapshot: snapshot)
            case .medium: GoMediumWidget(p: p, snapshot: snapshot)
            case .accessoryRectangular: GoRectangularWidget(p: p)
            case .accessoryCircular: GoCircularWidget(p: p)
            case .accessoryInline: GoInlineWidget(p: p)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(p.accessibilityText)
    }
}

// MARK: Idle and finished (system families)

private struct GoEmptyState: View {
    let p: GoPresentation
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: IterSpace.xs) {
            Image(systemName: p.isFinished ? "checkmark.circle.fill" : "car.fill")
                .font(.system(size: compact ? 20 : 26, weight: .semibold))
                .foregroundStyle(IterColor.textSecondary)
            Spacer(minLength: 0)
            Text(verbatim: p.isFinished ? String(localized: "Trip complete") : String(localized: "No trip running"))
                .font(IterFont.headline)
                .foregroundStyle(IterColor.textPrimary)
                .lineLimit(2)
            Text(verbatim: p.isFinished ? p.title : String(localized: "Open Iter to start"))
                .font(IterFont.caption)
                .foregroundStyle(IterColor.textSecondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: Small

private struct GoSmallWidget: View {
    let p: GoPresentation
    let snapshot: GoSnapshot

    var body: some View {
        if p.isIdle || p.isFinished {
            GoEmptyState(p: p.isFinished ? p.withTitle(snapshot.tripName) : p)
        } else {
            VStack(alignment: .leading, spacing: IterSpace.xs) {
                Text(verbatim: p.title)
                    .font(IterFont.headline)
                    .foregroundStyle(IterColor.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
                GoHeadline(p: p, size: 28)
                HStack(spacing: IterSpace.xs) {
                    GoChip(p: p, size: .compact, timeStyle: .none)
                    if p.ageText == nil, let line = p.clockLine {
                        Text(verbatim: line).font(IterFont.caption).foregroundStyle(IterColor.textSecondary).lineLimit(1).minimumScaleFactor(0.7)
                    }
                }
                GoAgeLine(p: p, font: IterFont.caption)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

// MARK: Medium

private struct GoMediumWidget: View {
    let p: GoPresentation
    let snapshot: GoSnapshot

    private var then: GoScheduleItem? {
        guard let schedule = snapshot.schedule, schedule.count > 1 else { return nil }
        return schedule[1]
    }

    var body: some View {
        if p.isIdle || p.isFinished {
            GoEmptyState(p: p.isFinished ? p.withTitle(snapshot.tripName) : p)
        } else {
            HStack(alignment: .top, spacing: IterSpace.lg) {
                VStack(alignment: .leading, spacing: IterSpace.xs) {
                    Text(verbatim: snapshot.tripName)
                        .font(IterFont.caption)
                        .foregroundStyle(IterColor.textSecondary)
                        .lineLimit(1)
                    Text(verbatim: p.title)
                        .font(IterFont.headline)
                        .foregroundStyle(IterColor.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                    Spacer(minLength: 0)
                    GoHeadline(p: p, size: 30)
                    GoAgeLine(p: p, font: IterFont.caption)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                VStack(alignment: .trailing, spacing: IterSpace.xs) {
                    GoChip(p: p, size: .large, timeStyle: .start)
                    if let word = p.scoreKindWord {
                        Text(verbatim: word).font(IterFont.caption).foregroundStyle(IterColor.textSecondary)
                    }
                    Spacer(minLength: 0)
                    if let line = p.clockLine {
                        Text(verbatim: line).font(IterFont.subheadline).foregroundStyle(IterColor.textPrimary).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    if let then {
                        Text(verbatim: String(localized: "Then \(then.stop.name)"))
                            .font(IterFont.caption)
                            .foregroundStyle(IterColor.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .frame(width: 128, alignment: .trailing)
                .frame(maxHeight: .infinity, alignment: .topTrailing)
            }
        }
    }
}

// MARK: Accessories (monochrome-friendly: system styles only, no colour-only meaning, accent on the key element)

private struct GoRectangularWidget: View {
    let p: GoPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                if let kind = p.content.windowKind {
                    Image(systemName: LightText.symbol(kind)).symbolRenderingMode(.monochrome).font(.system(size: 12, weight: .semibold))
                } else {
                    Image(systemName: p.isFinished ? "checkmark.circle.fill" : "car.fill").font(.system(size: 12, weight: .semibold))
                }
                Text(verbatim: p.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 0)
                if let score = p.score {
                    Text(score, format: .number).font(.system(size: 13, weight: .semibold)).monospacedDigit()
                        .opacity(p.isLowConfidence ? 0.7 : 1)
                }
            }
            .widgetAccentable()
            if p.isIdle || p.isFinished {
                Text(verbatim: p.isIdle ? String(localized: "Open Iter to start") : String(localized: "Trip complete"))
                    .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
            } else if let status = p.status, p.countdown == nil {
                Label { Text(verbatim: status.text) } icon: {
                    if let s = GoHeadline.symbol(status.tone, phase: p.phase) { Image(systemName: s) }
                }
                .font(.system(size: 16, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
            } else if let countdown = p.countdown {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(verbatim: countdown.label).font(.system(size: 11)).foregroundStyle(.secondary)
                    GoCountdownText(target: countdown.target, clock: p.clock, font: .system(size: 20, weight: .semibold))
                }
                if let status = p.status {
                    Label { Text(verbatim: status.text) } icon: { Image(systemName: "exclamationmark.triangle.fill") }
                        .font(.system(size: 11, weight: .semibold)).lineLimit(1)
                }
            }
            if let age = p.ageText {
                Label { Text(verbatim: age) } icon: { Image(systemName: p.content.isOffline ? "wifi.slash" : "clock.arrow.circlepath") }
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
            } else if let line = p.clockLine {
                Text(verbatim: line).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

private struct GoCircularWidget: View {
    let p: GoPresentation

    var body: some View {
        // The icon says when the numbers are not current: offline, or old.
        let marker = p.content.isOffline ? "wifi.slash" : (p.isOld || p.isStale ? "clock.arrow.circlepath" : nil)
        if let score = p.score, p.countdown == nil, let marker {
            // Old or offline: no gauge (it would look current), a plain number with the hint beside it.
            VStack(spacing: 0) {
                Image(systemName: marker).font(.system(size: 13, weight: .semibold)).widgetAccentable()
                Text(score, format: .number).font(.system(size: 24, weight: .semibold)).monospacedDigit()
                Text(verbatim: String(localized: "Last")).font(.system(size: 9)).foregroundStyle(.secondary)
            }
        } else if let score = p.score, p.countdown == nil {
            Gauge(value: Double(score), in: 0...100) {
                Image(systemName: marker ?? p.content.windowKind.map { LightText.symbol($0) } ?? "sun.max.fill")
            } currentValueLabel: {
                Text(score, format: .number).monospacedDigit()
            }
            .gaugeStyle(.accessoryCircularCapacity)
        } else if let countdown = p.countdown {
            VStack(spacing: 0) {
                Image(systemName: marker ?? (p.phase == .driving ? "car.fill" : (p.phase == .atStop ? p.content.windowKind.map { LightText.symbol($0) } ?? "clock" : "figure.walk.departure"))).font(.system(size: 12, weight: .semibold))
                    .widgetAccentable()
                GoCountdownText(target: countdown.target, clock: p.clock, font: .system(size: 13, weight: .semibold), alignment: .center, lineLimit: 2)
                    .frame(width: 58)
            }
        } else {
            VStack(spacing: 0) {
                let symbol = p.status.flatMap { GoHeadline.symbol($0.tone, phase: p.phase) } ?? (p.isFinished ? "checkmark.circle.fill" : "car.fill")
                Image(systemName: symbol).font(.system(size: 20, weight: .semibold)).widgetAccentable()
                Text(verbatim: p.isIdle ? String(localized: "Iter") : (p.status?.text ?? p.shortLabel))
                    .font(.system(size: 10, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.6)
            }
        }
    }
}

private struct GoInlineWidget: View {
    let p: GoPresentation

    var body: some View {
        if p.isIdle {
            Label { Text(verbatim: String(localized: "No trip running")) } icon: { Image(systemName: "car.fill") }
        } else if p.isFinished {
            Label { Text(verbatim: String(localized: "Trip complete")) } icon: { Image(systemName: "checkmark.circle.fill") }
        } else if let countdown = p.countdown {
            Label {
                (Text(verbatim: "\(p.phase == .driving ? String(localized: "Arrive in") : (p.phase == .atStop && p.countdown?.target == p.content.windowEnd ? String(localized: "Ends in") : String(localized: "Leave in"))) ")
                 + GoCountdownText.text(target: countdown.target, clock: p.clock)
                 + Text(verbatim: p.score.map { " · \($0)" } ?? ""))
            } icon: {
                Image(systemName: p.content.windowKind.map { LightText.symbol($0) } ?? "car.fill")
            }
            .minimumScaleFactor(0.8)
        } else if let status = p.status {
            Label { Text(verbatim: status.text + (p.score.map { " · \($0)" } ?? "")) } icon: {
                Image(systemName: GoHeadline.symbol(status.tone, phase: p.phase) ?? "car.fill")
            }
        }
    }
}

extension GoPresentation {
    /// The same presentation under another title (the trip name when the run is over).
    func withTitle(_ title: String) -> GoPresentation {
        var c = content
        c.nextStopName = title.isEmpty ? nil : title
        return GoPresentation(c, clock: clock, zone: zone, isStale: isStale)
    }
}
