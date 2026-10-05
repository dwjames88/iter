import SwiftUI
import IterCore
import IterDesign
import IterFeatures

/// Apple Weather attribution: the mark and the legal link, required wherever WeatherKit data appears.
/// When the scores come from sample data, says that instead (sample data is not Apple Weather).
struct WeatherAttributionView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if model.sampleDataEnabled {
            SampleDataLabel(style: .inline)
        } else if let info = model.attribution {
            HStack(spacing: IterSpace.sm) {
                AsyncImage(url: colorScheme == .dark ? info.combinedMarkDarkURL : info.combinedMarkLightURL) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    Text(info.serviceName).font(IterFont.caption)
                }
                .frame(height: IterSize.iconSmall)
                .accessibilityLabel(info.serviceName)
                Link(String(localized: "Legal attribution", comment: "Link to Apple Weather legal attribution"), destination: info.legalPageURL)
                    .font(IterFont.caption)
                Text("Light Index modified from forecast data", comment: "Value-added data notice under weather")
                    .font(IterFont.caption)
                    .foregroundStyle(IterColor.textTertiary)
            }
        }
    }
}
