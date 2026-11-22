import Foundation
import MapKit
import IterModel

/// FeatureKind <-> `MKPointOfInterestCategory`. Pure.
///
/// MapKit's category list is short and mostly urban, so only kinds with an honest category are mapped:
///
/// - `.beach` -> `.beach`
/// - `.castle` -> `.castle`, `.fortress`
/// - `.viewpoint` -> `.scenicView` (an iOS 27 / macOS 27 category; nothing on 26)
///
/// Every other kind (peak, lake, waterfall, arch, lighthouse, canyon, glacier, hot spring, cave, bridge) has no
/// MapKit category. Parks, hiking and landmarks are not used as stand-ins: a park is not a peak, and labelling it
/// as one would put wrong kinds on a candidate. Asking for those kinds returns [] without a request; use OSM.
enum POICategoryMapping {
    static func categories(for kind: FeatureKind) -> [MKPointOfInterestCategory] {
        switch kind {
        case .beach: return [.beach]
        case .castle: return [.castle, .fortress]
        case .viewpoint:
            if #available(macOS 27, iOS 27, *) { return [.scenicView] }
            return []
        case .peak, .lake, .waterfall, .arch, .lighthouse, .canyon, .glacier, .hotSpring, .cave, .bridge:
            return []
        }
    }

    /// Union of the categories for several kinds, in a stable order, without duplicates.
    static func categories(for kinds: Set<FeatureKind>) -> [MKPointOfInterestCategory] {
        var seen = Set<String>()
        var out: [MKPointOfInterestCategory] = []
        for kind in FeatureKind.allCases where kinds.contains(kind) {
            for c in categories(for: kind) where seen.insert(c.rawValue).inserted { out.append(c) }
        }
        return out
    }

    /// The kinds a category evidences, from its raw value. Empty for categories that say nothing about a feature.
    static func featureKinds(forCategoryRaw raw: String?) -> [FeatureKind] {
        guard let raw else { return [] }
        let c = MKPointOfInterestCategory(rawValue: raw)
        switch c {
        case .beach: return [.beach]
        case .castle, .fortress: return [.castle]
        default:
            if #available(macOS 27, iOS 27, *), c == .scenicView { return [.viewpoint] }
            return []
        }
    }
}
