import Foundation
import IterModel
#if canImport(MapKit)
import MapKit
#endif

/// Hands a destination to Apple Maps for turn-by-turn. The UI opens it (`openURL` or `MKMapItem.openInMaps`).
public struct NavigationHandoff: Hashable, Sendable {
    public var destination: Coordinate
    public var name: String

    public init(destination: Coordinate, name: String) {
        self.destination = destination
        self.name = name
    }

    /// `https://maps.apple.com/?daddr=<lat>,<lon>&dirflg=d&q=<name>`
    public var appleMapsURL: URL {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+?#/:;,@$")
        let q = name.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        let lat = String(format: "%.6f", destination.latitude)
        let lon = String(format: "%.6f", destination.longitude)
        return URL(string: "https://maps.apple.com/?daddr=\(lat),\(lon)&dirflg=d&q=\(q)")!
    }

    #if canImport(MapKit)
    public func mapItem() -> MKMapItem {
        let item = MKMapItem(location: CLLocation(latitude: destination.latitude, longitude: destination.longitude), address: nil)
        item.name = name
        return item
    }

    public var launchOptions: [String: Any] {
        [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving]
    }
    #endif
}
