import SwiftUI
import IterCore
import IterDesign

/// The trailing score chip of a list row, shared by Explore and Saved: the chip (symbol, start time and score) trail-aligned
/// in a fixed-width lane, `ScoreChip.maxWidth(size:timeStyle:)`, so chips stack and align across every row.
struct EventLane: View {
    /// nil: the row has no window; the lane stays empty at full width so the label lane does not move.
    let window: LightWindow?
    let zone: TimeZone
    var size: ScoreChip.Size = .small
    var isLoading = false
    var isTomorrow = false

    /// The lane's width.
    static func width(_ size: ScoreChip.Size) -> CGFloat {
        ScoreChip.maxWidth(size: size, timeStyle: .start)
    }

    var body: some View {
        if let window {
            ScoreChip(window: window, zone: zone, timeStyle: .start, size: size, isLoading: isLoading, isTomorrow: isTomorrow)
                .frame(width: Self.width(size), alignment: .trailing)
        } else {
            Color.clear.frame(width: Self.width(size), height: ScoreChip.height(size))
        }
    }
}

extension LayoutLane {
    /// The lanes of a regular-size list row with a start time, for `.layoutGrid(lanes:)`.
    @MainActor static func eventRow(disclosure: Bool = false) -> [LayoutLane] {
        standardRowLanes(disclosure: disclosure, event: .small, time: .start)
    }
}
