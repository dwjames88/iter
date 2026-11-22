import Foundation
import IterModel

/// Route and ETA mapping. Pure.
enum MapKitDirectionsMapping {
    /// Most points kept on a route path.
    static let maxPathPoints = 400

    static func route(path: [Coordinate], seconds: TimeInterval, meters: Double, departing: Date?, from: Coordinate, to: Coordinate) -> Route {
        let thinned = MapKitConversion.downsample(path, maxPoints: maxPathPoints)
        return Route(path: thinned.isEmpty ? [from, to] : thinned, seconds: seconds, meters: meters, departing: departing,
                     isTrafficAware: departing != nil, isEstimate: false)
    }

    /// `arrival` may be nil when MapKit gives none; it is then departure plus travel time.
    static func eta(seconds: TimeInterval, arrival: Date?, departing: Date) -> ETA {
        ETA(seconds: seconds, arrival: arrival ?? departing.addingTimeInterval(seconds), departing: departing)
    }
}
