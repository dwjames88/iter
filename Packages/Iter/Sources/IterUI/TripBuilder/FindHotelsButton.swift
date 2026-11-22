import SwiftUI

/// "Find hotels": a plain link-style button in the warning colour that opens Apple Maps searching Hotels near a place.
/// Figma part: find hotels button.
public struct FindHotelsButton: View {
    public let latitude: Double
    public let longitude: Double
    @Environment(\.openURL) private var openURL

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    /// The Maps URL: a search for "Hotels" centred on the place (`maps://?q=Hotels&sll=lat,lon`).
    public static func url(latitude: Double, longitude: Double) -> URL? {
        URL(string: "maps://?q=Hotels&sll=\(latitude),\(longitude)")
    }

    public var url: URL? { Self.url(latitude: latitude, longitude: longitude) }

    public var body: some View {
        Button {
            if let url { openURL(url) }
        } label: {
            Text("Find hotels", bundle: .module, comment: "Button on an overnight: opens Apple Maps searching for hotels there")
                .font(BuilderType.body)
                .foregroundStyle(IterColor.warning)
        }
        .buttonStyle(.plain)
        .help(Text("Search Apple Maps for hotels near this overnight", bundle: .module, comment: "Tooltip"))
    }
}
