import Foundation
import IterModel

/// Shared helpers for the MediaWiki action API (Wikipedia and Commons). Pure.
enum WikimediaAPI {
    /// The API's largest geosearch radius, metres.
    static let maxRadiusM = 10_000.0
    static let minRadiusM = 10.0

    static func clampRadius(_ r: Double) -> Int { Int(min(maxRadiusM, max(minRadiusM, r)).rounded()) }

    /// "36.5785" style: up to 6 decimals, trailing zeros dropped.
    static func degrees(_ v: Double) -> String {
        var s = String(format: "%.6f", v)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s == "-0" ? "0" : s
    }

    /// `LAT%7CLON`, the way the recorded requests spell it.
    static func coordParam(_ c: Coordinate) -> String { degrees(c.latitude) + "%7C" + degrees(c.longitude) }

    /// An API error body (`{"error":{"code":..,"info":..}}`) as text, else nil.
    static func errorText(in object: [String: Any]) -> String? {
        guard let e = object["error"] as? [String: Any] else { return nil }
        return [e["code"] as? String, e["info"] as? String].compactMap { $0 }.joined(separator: ": ")
    }

    /// The half-extent of the area in metres: the larger of the half height and half width at the centre latitude.
    static func radius(of area: DiscoveryArea) -> Double {
        let r = area.region
        let halfLat = r.latitudeDelta / 2 * 111_320
        let halfLon = r.longitudeDelta / 2 * 111_320 * max(0.05, cos(r.center.latitude * .pi / 180))
        return max(halfLat, halfLon)
    }
}
