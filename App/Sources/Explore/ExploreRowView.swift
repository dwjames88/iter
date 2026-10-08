import SwiftUI
import IterCore
import IterData
import IterDesign
import IterFeatures

/// One list row: the spot (name, then one quiet locality line), then its next sunrise or sunset as one event unit in
/// fixed lanes (see `EventLane`). A click selects the row; it is not a button that expands.
///
/// Equatable, and drawn with `.equatable()`: a row whose spot, score and distance did not change is not rebuilt when
/// another row's score lands. It takes no hover state: the pointer over a row emphasises its pin on the map, and a
/// list that read `hoveredID` would be re-evaluated on every move between rows.
struct ExploreRowView: View, Equatable {
    let row: ExploreRow
    /// Shown after the locality ("Big Sur, CA · 42 mi") when there is a location to measure from.
    var showsDistance = false

    var body: some View {
        let _ = IterPerf.count("row.body")
        summary
            .padding(.vertical, IterSpace.sm)
            .frame(minHeight: IterGrid.rowDouble, alignment: .leading)
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(LightText.rowDescription(row, showsDistance: showsDistance))
    }

    private var summary: some View {
        HStack(alignment: .firstTextBaseline, spacing: IterGrid.laneGap) {
            VStack(alignment: .leading, spacing: IterSpace.xs) {
                Text(row.spot.name)
                    .font(IterFont.headline)
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
                .font(IterFont.secondary)
                .foregroundStyle(IterColor.textSecondary)
            }
            Spacer(minLength: 0)
            EventLane(window: row.window, zone: row.spot.timeZone, isLoading: row.isLoading, isTomorrow: LightText.isTomorrow(row))
        }
    }
}
