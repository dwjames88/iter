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
        HStack(spacing: IterSpace.md) {
            Image(systemName: LightText.symbol(spot.category))
                .font(.title3)
                .foregroundStyle(IterColor.textSecondary)
                .frame(width: IterSize.lightRingSmall)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: IterSpace.xxs) {
                Text(spot.name).font(IterFont.headline).lineLimit(1)
                HStack(spacing: IterSpace.sm) {
                    Text(spot.locality.isEmpty ? LightText.name(spot.category) : spot.locality)
                        .font(IterFont.subheadline)
                        .foregroundStyle(IterColor.textSecondary)
                        .lineLimit(1)
                    ProvenanceTag(origin: spot.origin)
                }
            }
            Spacer(minLength: IterSpace.sm)
            if let next {
                WindowLightLine(window: next.window, zone: spot.timeZone, isLoading: model.forecasts.isLoading(spot.coordinate),
                                isTomorrow: next.day > model.today(in: spot.timeZone))
            }
        }
        .padding(.vertical, IterSpace.xs)
        .accessibilityElement(children: .combine)
    }
}
