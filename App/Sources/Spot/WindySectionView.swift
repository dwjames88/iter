import SwiftUI
import IterCore
import IterDesign

/// Windy's map shows cloud by height, rain and wind around the spot. Windy does not allow its map inside other
/// weather apps, so this opens windy.com in the browser instead of embedding anything.
struct WindySection: View {
    let coordinate: Coordinate
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: IterSpace.md) {
            Text(LightText.windyTitle).font(IterFont.titleSection)
            SpotCard {
                HStack(alignment: .center, spacing: IterSpace.md) {
                    Text(LightText.windyExplanation)
                        .font(IterFont.callout)
                        .foregroundStyle(IterColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: IterSpace.md)
                    Button {
                        openURL(WindyLink.url(center: coordinate, zoom: WindyLink.spotZoom))
                    } label: {
                        Label(LightText.openInWindy, systemImage: "arrow.up.forward.square")
                    }
                    .help(String(localized: "Open this spot on windy.com in your browser", comment: "Tooltip"))
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}
