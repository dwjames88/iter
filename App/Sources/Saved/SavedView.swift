import SwiftUI
import IterCore
import IterData
import IterDesign
import IterFeatures

/// A spot's next sunrise or sunset as the Locations row and the Locations map pin both draw it.
struct SavedEvent {
    let window: LightWindow
    let isLoading: Bool
    let isTomorrow: Bool
}

extension AppModel {
    /// The one place the Locations row and its map pin get their window, so they always agree.
    func savedEvent(for spot: Spot) -> SavedEvent? {
        nextLight(for: spot).map { next in
            SavedEvent(window: next.window, isLoading: forecasts.isLoading(spot.coordinate), isTomorrow: next.day > today(in: spot.timeZone))
        }
    }
}

/// One row of Locations: the spot, where it is and its next light. (The screen is `LocationsView`.)
struct SavedRow: View {
    @Environment(AppModel.self) private var model
    let item: SavedItem

    var body: some View {
        let spot = item.spot
        let next = model.savedEvent(for: spot)
        HStack(alignment: .firstTextBaseline, spacing: IterGrid.laneGap) {
            Image(systemName: LightText.symbol(spot.category))
                .font(IterFont.body)
                .foregroundStyle(IterColor.textSecondary)
                .frame(width: IterGrid.disclosureLane)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: IterSpace.xs) {
                Text(spot.name)
                    .font(IterFont.headline)
                    .foregroundStyle(IterColor.textPrimary)
                    .lineLimit(1)
                HStack(spacing: IterSpace.xs) {
                    Text(spot.locality.isEmpty ? LightText.name(spot.category) : spot.locality)
                        .lineLimit(1)
                    Text(verbatim: "·").accessibilityHidden(true)
                    ProvenanceTag(origin: spot.origin)
                }
                .font(IterFont.secondary)
                .foregroundStyle(IterColor.textSecondary)
            }
            Spacer(minLength: 0)
            EventLane(window: next?.window, zone: spot.timeZone, isLoading: model.forecasts.isLoading(spot.coordinate),
                      isTomorrow: next?.isTomorrow ?? false)
        }
        .padding(.vertical, IterSpace.sm)
        .frame(minHeight: IterGrid.rowDouble, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
