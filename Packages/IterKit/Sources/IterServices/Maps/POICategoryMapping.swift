import Foundation
import MapKit
import IterCore

/// Maps MapKit point-of-interest categories (by raw value, so IterCore stays MapKit-free) to Iter's spot categories.
public enum POICategoryMapping {
    /// Categories worth asking MapKit for when looking for places to shoot.
    public static let scenicCategories: [String] = baseScenicCategories + extraScenicCategories

    private static var extraScenicCategories: [String] {
        // `scenicView` first appears in the macOS 27 SDK; the deployment target is 26.
        if #available(macOS 27, iOS 27, *) { return [MKPointOfInterestCategory.scenicView.rawValue] }
        return []
    }

    private static let baseScenicCategories: [String] = [
        MKPointOfInterestCategory.nationalPark,
        .park,
        .beach,
        .campground,
        .landmark,
        .nationalMonument,
        .hiking,
        .marina,
        .castle,
        .fortress,
        .rockClimbing,
    ].map(\.rawValue)

    public static func spotCategory(for poiCategoryRawValue: String?) -> SpotCategory {
        guard let raw = poiCategoryRawValue else { return .landscape }
        let c = MKPointOfInterestCategory(rawValue: raw)
        switch c {
        case .nationalPark, .park, .hiking, .campground, .rvPark, .rockClimbing, .skiing:
            return .landscape
        case .beach, .marina, .surfing, .kayaking, .swimming, .fishing:
            return .coast
        case .zoo, .animalService:
            return .wildlife
        case .planetarium:
            return .astro
        case .castle, .fortress, .landmark, .nationalMonument, .museum, .theater, .library, .university, .stadium, .airport, .publicTransport:
            return .architecture
        case .nightlife, .restaurant, .cafe, .musicVenue, .amusementPark, .fairground, .store, .hotel, .conventionCenter:
            return .urban
        default:
            return .landscape
        }
    }
}
