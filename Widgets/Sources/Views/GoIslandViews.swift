import IterGoActivity
import IterModel
import IterUI
import SwiftUI

// Dynamic Island presentations. The island is always black, so these views draw in the dark colour scheme whatever the phone's
// appearance is. Takes values only; the extension wraps each in its `DynamicIsland` region.

private struct IslandSurface<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View { content.environment(\.colorScheme, .dark) }
}

/// Compact leading: the window symbol and a one-word label ("Leave", "Arrive", "Late", "Paused").
struct GoIslandCompactLeading: View {
    let content: GoActivityContent
    let clock: GoClock
    var isStale = false
    var zone: TimeZone = .current

    var body: some View {
        let p = GoPresentation(content, clock: clock, zone: zone, isStale: isStale)
        IslandSurface {
            HStack(spacing: 4) {
                if let kind = content.windowKind {
                    Image(systemName: LightText.symbol(kind))
                        .symbolRenderingMode(.monochrome)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(p.isDim ? IterColor.textSecondary : IterColor.textPrimary)
                } else {
                    Image(systemName: "car.fill").font(.system(size: 13, weight: .semibold)).foregroundStyle(IterColor.textPrimary)
                }
                Text(verbatim: p.shortLabel)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(p.status?.tone == .warning ? IterColor.warning : IterColor.textPrimary.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(p.accessibilityText)
    }
}

/// Compact trailing: the countdown in a fixed width so the island does not change size as the digits change.
struct GoIslandCompactTrailing: View {
    static let width: CGFloat = 52
    let content: GoActivityContent
    let clock: GoClock
    var isStale = false
    var zone: TimeZone = .current

    var body: some View {
        let p = GoPresentation(content, clock: clock, zone: zone, isStale: isStale)
        IslandSurface {
            Group {
                if let countdown = p.countdown {
                    GoCountdownText(target: countdown.target, clock: clock, font: .system(size: 13, weight: .semibold), alignment: .trailing)
                        .foregroundStyle(p.isDim ? IterColor.textSecondary : IterColor.textPrimary)
                } else if let status = p.status {
                    Image(systemName: GoHeadline.symbol(status.tone, phase: p.phase) ?? "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(GoHeadline.color(status.tone))
                } else {
                    Text(verbatim: "–").font(.system(size: 13, weight: .semibold)).foregroundStyle(IterColor.textSecondary)
                }
            }
            .frame(width: Self.width, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(p.accessibilityText)
    }
}

/// Minimal: the score in a ring (the ramp colour at the score), else the window symbol, else the car.
struct GoIslandMinimal: View {
    let content: GoActivityContent
    let clock: GoClock
    var isStale = false

    var body: some View {
        let p = GoPresentation(content, clock: clock, isStale: isStale)
        IslandSurface {
            Group {
                if let score = p.score {
                    ZStack {
                        Circle().stroke(IterColor.textTertiary, lineWidth: 2.5)
                        Circle().trim(from: 0, to: CGFloat(score) / 100)
                            .stroke(IterColor.ramp(score: score), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text(score, format: .number)
                            .font(.system(size: 11, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(p.isDim ? IterColor.textSecondary : IterColor.textPrimary)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(width: 24, height: 24)
                    .opacity(p.isLowConfidence ? IterEvent.lowConfidenceOpacity : 1)
                } else if let kind = content.windowKind {
                    Image(systemName: LightText.symbol(kind)).font(.system(size: 15, weight: .semibold)).foregroundStyle(IterColor.textPrimary)
                } else {
                    Image(systemName: "car.fill").font(.system(size: 14, weight: .semibold)).foregroundStyle(IterColor.textPrimary)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(p.accessibilityText)
    }
}

/// Expanded, leading region: the next stop and its window.
struct GoIslandExpandedLeading: View {
    let content: GoActivityContent
    let clock: GoClock
    var isStale = false
    var zone: TimeZone = .current

    var body: some View {
        let p = GoPresentation(content, clock: clock, zone: zone, isStale: isStale)
        IslandSurface {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: p.title)
                    .font(IterFont.headline)
                    .foregroundStyle(IterColor.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                if let kind = content.windowKind, let start = content.windowStart {
                    HStack(spacing: 4) {
                        Image(systemName: LightText.symbol(kind)).symbolRenderingMode(.monochrome)
                        Text(verbatim: "\(LightText.shortName(kind)) \(TimeText.time(start, in: zone))").monospacedDigit()
                    }
                    .font(IterFont.subheadline)
                    .foregroundStyle(IterColor.textSecondary)
                    .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Expanded, trailing region: the live and the forecast score side by side, each named.
struct GoIslandExpandedTrailing: View {
    let content: GoActivityContent
    let clock: GoClock
    var isStale = false

    var body: some View {
        let p = GoPresentation(content, clock: clock, isStale: isStale)
        IslandSurface {
            HStack(alignment: .top, spacing: 10) {
                if content.liveScore != nil { column(String(localized: "Live"), content.liveScore, p) }
                if content.forecastScore != nil { column(String(localized: "Forecast"), content.forecastScore, p) }
            }
        }
    }

    private func column(_ title: String, _ score: Int?, _ p: GoPresentation) -> some View {
        VStack(spacing: 2) {
            Text(verbatim: title).font(IterFont.caption).foregroundStyle(IterColor.textSecondary).lineLimit(1)
            if let score {
                Text(score, format: .number)
                    .font(.system(size: 22, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(p.isDim ? IterColor.textSecondary.color : IterColor.ramp(score: score))
                    .opacity(p.isLowConfidence ? IterEvent.lowConfidenceOpacity : 1)
            }
        }
    }
}

/// Expanded, bottom region: the big countdown and the clock line, the age, and the Navigate link.
struct GoIslandExpandedBottom: View {
    let content: GoActivityContent
    let clock: GoClock
    var isStale = false
    var zone: TimeZone = .current
    var navigateURL: URL = GoDeepLink.navigate()

    var body: some View {
        let p = GoPresentation(content, clock: clock, zone: zone, isStale: isStale)
        IslandSurface {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: IterSpace.md) {
                    GoHeadline(p: p, size: 26)
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 2) {
                        if let line = p.clockLine {
                            Text(verbatim: line).font(IterFont.subheadline).foregroundStyle(IterColor.textSecondary).lineLimit(1)
                        }
                        if !p.isIdle, !p.isFinished {
                            Link(destination: navigateURL) {
                                Label { Text("Navigate") } icon: { Image(systemName: "location.fill") }
                                    .font(.system(size: 14, weight: .semibold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(IterColor.accent, in: Capsule())
                                    .foregroundStyle(IterColor.onAccent)
                            }
                        }
                    }
                }
                GoAgeLine(p: p)
            }
        }
    }
}

/// All four expanded regions arranged as the island lays them out: leading and trailing beside the camera cut-out (here a
/// gap), the bottom region below. Used by the hosted renders; the extension places the regions itself.
struct GoIslandExpandedPreview: View {
    let content: GoActivityContent
    let clock: GoClock
    var isStale = false
    var zone: TimeZone = .current

    var body: some View {
        VStack(alignment: .leading, spacing: IterSpace.sm) {
            HStack(alignment: .top) {
                GoIslandExpandedLeading(content: content, clock: clock, isStale: isStale, zone: zone)
                Spacer(minLength: 96)
                GoIslandExpandedTrailing(content: content, clock: clock, isStale: isStale)
            }
            GoIslandExpandedBottom(content: content, clock: clock, isStale: isStale, zone: zone)
        }
        .padding(.horizontal, IterSpace.xl)
        .padding(.vertical, IterSpace.lg)
        .environment(\.colorScheme, .dark)
    }
}
