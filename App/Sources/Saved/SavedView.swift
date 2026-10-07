import SwiftUI
import IterCore
import IterData
import IterDesign
import IterFeatures

/// One row of Locations: the spot, where it is and its next light. (The screen is `LocationsView`.)
struct SavedRow: View {
    @Environment(AppModel.self) private var model
    let item: SavedItem

    var body: some View {
        let spot = item.spot
        let next = model.nextLight(for: spot)
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
                    ProvenanceTag(origin: spot.origin)
                }
                .font(IterFont.secondary)
                .foregroundStyle(IterColor.textSecondary)
            }
            Spacer(minLength: 0)
            EventLane(window: next?.window, zone: spot.timeZone, isLoading: model.forecasts.isLoading(spot.coordinate),
                      isTomorrow: next.map { $0.day > model.today(in: spot.timeZone) } ?? false)
        }
        .padding(.vertical, IterSpace.sm)
        .frame(minHeight: IterGrid.rowDouble, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
