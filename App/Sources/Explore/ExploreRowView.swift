import SwiftUI
import IterCore
import IterData
import IterDesign
import IterFeatures

/// One list row: the spot, then its next sunrise or sunset in three fixed lanes (window symbol, score chip, start
/// time; see `ExploreRowLayout`). A click selects the row; it is not a button that expands.
struct ExploreRowView: View {
    let row: ExploreRow
    var isHovered = false
    /// Shown after the locality ("Big Sur, CA · 42 mi") when there is a location to measure from.
    var showsDistance = false

    var body: some View {
        summary
            .padding(.vertical, IterSpace.xs)
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(LightText.rowDescription(row, showsDistance: showsDistance))
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
                WindowSymbol(kind: window.kind)
                    .frame(width: lanes.symbolLane)
                chip(window)
                    .frame(width: lanes.chipLane)
                Text(LightText.startTime(window, in: row.spot.timeZone) ?? "")
                    .font(IterFont.timeSmall)
                    .foregroundStyle(IterColor.textSecondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .frame(width: lanes.timeLane, alignment: .trailing)
                    .help(LightText.isTomorrow(row)
                          ? String(localized: "Tomorrow", comment: "Tooltip on a row's start time: the next window is tomorrow")
                          : "")
            }
        } else {
            Color.clear.frame(width: lanes.total, height: IterSize.badgeHeight)
        }
    }

    @ViewBuilder private func chip(_ window: LightWindow) -> some View {
        switch window.assessment {
        case .scored(let score):
            ScoreChip(score: score, size: .regular)
        case .noForecast:
            if row.isLoading { ProgressView().controlSize(.small) } else { Color.clear }
        }
    }
}
