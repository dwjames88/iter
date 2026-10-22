import SwiftUI
import IterCore
import IterDesign

/// "Find hotels": a plain link-style button in the warning violet that opens Apple Maps searching Hotels near a place.
struct FindHotelsButton: View {
    let latitude: Double
    let longitude: Double
    @Environment(\.openURL) private var openURL

    init(coordinate: Coordinate) {
        latitude = coordinate.latitude
        longitude = coordinate.longitude
    }

    /// The Maps URL: a search for "Hotels" centred on the place.
    var url: URL? { URL(string: "maps://?q=Hotels&sll=\(latitude),\(longitude)") }

    var body: some View {
        Button {
            if let url { openURL(url) }
        } label: {
            Text("Find hotels", comment: "Button on an overnight: opens Apple Maps searching for hotels there")
                .font(BuilderType.body)
                .foregroundStyle(IterColor.warning)
        }
        .buttonStyle(.plain)
        .help(Text("Search Apple Maps for hotels near this overnight", comment: "Tooltip"))
    }
}

#Preview("Find hotels, light") { FindHotelsButton(coordinate: Coordinate(latitude: 36.9, longitude: -111.45)).padding(IterSpace.xl).background(IterColor.backgroundContent).preferredColorScheme(.light) }
#Preview("Find hotels, dark") { FindHotelsButton(coordinate: Coordinate(latitude: 36.9, longitude: -111.45)).padding(IterSpace.xl).background(IterColor.backgroundContent).preferredColorScheme(.dark) }
