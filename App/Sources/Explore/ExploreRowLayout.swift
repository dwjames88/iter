import SwiftUI
import IterCore
import IterDesign

/// The trailing event unit of a list row, shared by Explore and Saved: one capsule (symbol, score and start time) in
/// a fixed-width trailing lane, `EventScore.unitWidth(variant, .start)`, so units stack and align across every row.
struct EventLane: View {
    /// nil: the row has no window; the lane stays empty at full width so the label lane does not move.
    let window: LightWindow?
    let zone: TimeZone
    var variant: EventScore.Variant = .regular
    var isLoading = false
    var isTomorrow = false

    /// The unit's width.
    static func width(_ variant: EventScore.Variant) -> CGFloat {
        EventScore.unitWidth(variant, timeStyle: .start)
    }

    var body: some View {
        if let window {
            EventScore(window: window, zone: zone, timeStyle: .start, variant: variant, isLoading: isLoading, isTomorrow: isTomorrow)
        } else {
            Color.clear.frame(width: Self.width(variant), height: EventScore.height(variant))
        }
    }
}

extension LayoutLane {
    /// The lanes of a regular-variant list row with a start time, for `.layoutGrid(lanes:)`.
    @MainActor static func eventRow(disclosure: Bool = false) -> [LayoutLane] {
        standardRowLanes(disclosure: disclosure, event: .regular, time: .start)
    }
}
