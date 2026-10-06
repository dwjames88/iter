import SwiftUI
import IterCore
import IterData
import IterDesign
import IterFeatures

/// One list row: the spot, then its light on the chosen day in three fixed lanes (chip, window name with band,
/// start time; see `ExploreRowLayout`). When the row is expanded, its actions and weather are the *next* list row
/// (`ExploreExpansionRow`), so the list's selection highlight stays on this summary line only.
struct ExploreRowView: View {
    let row: ExploreRow
    let day: LocalDay
    var isHovered = false
    var isExpanded = false
    /// Shown after the locality ("Big Sur, CA · 42 mi") when there is a location to measure from.
    var showsDistance = false
    /// A click on the summary line (not the expanded area).
    var onTap: () -> Void = {}

    var body: some View {
        summary
            .padding(.vertical, IterSpace.xs)
            .contentShape(Rectangle())
            .simultaneousGesture(TapGesture().onEnded { onTap() })
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(LightText.rowDescription(row, showsDistance: showsDistance))
            .accessibilityValue(isExpanded
                ? Text("Expanded", comment: "VoiceOver: the list row is open")
                : Text("Collapsed", comment: "VoiceOver: the list row is closed"))
            .accessibilityHint(Text("Shows or hides the save and trip buttons and the weather", comment: "VoiceOver hint on an Explore row"))
            .accessibilityAddTraits(.isButton)
    }

    private var summary: some View {
        HStack(alignment: .center, spacing: IterSpace.md) {
            VStack(alignment: .leading, spacing: IterSpace.xxs) {
                Text(row.spot.name)
                    .font(IterFont.bodyEmphasis)
                    .foregroundStyle(IterColor.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: IterSpace.xs) {
                    Text(row.spot.locality)
                        .lineLimit(1)
                    if showsDistance, let meters = row.distanceMeters {
                        // After the locality, and never the part that is cut off.
                        Text("· \(LightText.distance(meters: meters))")
                            .lineLimit(1)
                            .fixedSize()
                            .layoutPriority(1)
                    }
                    if row.source == .yours {
                        ProvenanceTag(origin: .user)
                    }
                }
                .font(IterFont.caption)
                .foregroundStyle(IterColor.textSecondary)
            }
            Spacer(minLength: 0)
            light
        }
    }

    @ViewBuilder private var light: some View {
        let lanes = ExploreRowLayout.metrics
        if let window = row.window {
            HStack(alignment: .center, spacing: ExploreRowLayout.laneGap) {
                chip(window)
                    .frame(width: lanes.chipLane)
                VStack(alignment: .leading, spacing: 0) {
                    Text(LightText.name(window.kind))
                        .font(IterFont.subheadline)
                        .foregroundStyle(IterColor.textPrimary)
                        .lineLimit(lanes.nameLines)
                        .fixedSize(horizontal: false, vertical: true)
                    detail(window)
                        .font(IterFont.caption)
                        .foregroundStyle(IterColor.textSecondary)
                }
                .frame(width: lanes.textLane, alignment: .leading)
                Text(LightText.startTime(window, in: row.spot.timeZone) ?? "")
                    .font(IterFont.timeSmall)
                    .foregroundStyle(IterColor.textSecondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .frame(width: lanes.timeLane, alignment: .trailing)
            }
        } else {
            Text(LightText.noWindowToday)
                .font(IterFont.caption)
                .foregroundStyle(IterColor.textSecondary)
                .multilineTextAlignment(.trailing)
                .frame(width: lanes.total, alignment: .trailing)
        }
    }

    @ViewBuilder private func chip(_ window: LightWindow) -> some View {
        switch window.assessment {
        case .scored(let score): ScoreChip(score: score, size: .regular)
        case .noForecast: NoForecastRing(diameter: IterSize.badgeHeight)
        }
    }

    @ViewBuilder private func detail(_ window: LightWindow) -> some View {
        switch window.assessment {
        case .scored(let score):
            HStack(spacing: IterSpace.xs) {
                Text(LightText.name(score.band))
                ConfidenceMark(confidence: score.confidence)
            }
        case .noForecast:
            Text(LightText.noForecast)
        }
    }
}
