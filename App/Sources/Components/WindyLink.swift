import Foundation
import IterCore

/// Links into windy.com. Windy's terms do not allow its map inside other weather apps, so Iter opens the
/// website at the place instead of embedding anything.
enum WindyLink {
    /// windy.com itself, the target of the required "Windy.com" attribution link.
    static let home = URL(string: "https://www.windy.com") ?? URL(filePath: "/")

    /// `https://www.windy.com/?LAT,LON,ZOOM`, coordinates to three decimal places, always with a dot.
    static func url(center: Coordinate, zoom: Int) -> URL {
        let text = "https://www.windy.com/?\(number(center.latitude)),\(number(center.longitude)),\(zoom)"
        return URL(string: text) ?? home
    }

    /// A web-Mercator zoom level for a map that spans `delta` degrees of latitude: about log2(360 / delta),
    /// clamped to the levels Windy shows sensibly (3 to 11).
    static func zoom(forLatitudeDelta delta: Double) -> Int {
        guard delta.isFinite, delta > 0 else { return maxZoom }
        let level = (log2(360 / delta)).rounded()
        return Int(min(Double(maxZoom), max(Double(minZoom), level)))
    }

    /// The zoom used for a single spot.
    static let spotZoom = 9

    private static let minZoom = 3
    private static let maxZoom = 11

    private static func number(_ value: Double) -> String {
        let rounded = (value * 1000).rounded() / 1000 + 0 // "+ 0" turns -0.0 into 0.0
        return String(format: "%.3f", rounded)
    }
}
