import Foundation
import IterModel
import IterSources

/// Pure mapping for NOAA HMS smoke KML (`hms_smokeYYYYMMDD.kml`).
///
/// Real structure (2025-08-15 file): `Document` with an `Overlay` folder (logos) and then one `Folder` per density named
/// `Smoke (Light)`, `Smoke (Medium)`, `Smoke (Heavy)`. Each `Placemark` has a CDATA `description` with
/// `Start Time: 2025227 1200UTC<br>End Time: ...<br>Density: Light<br>Satellite: GOES-WEST` (year, day of year, HHmm UTC),
/// a `styleUrl`, and one `Polygon` whose `outerBoundaryIs` ring is `lon,lat,alt` triples (`innerBoundaryIs` rings, none in
/// the recorded files, are read as holes). An empty day has no placemarks at all.
public enum HMSMapping {
    /// One analyst polygon (a placemark).
    public struct Placemark: Sendable, Equatable {
        public var density: SmokeAnalysis.Density
        /// Outer ring first, then holes: even-odd containment as `GeoPolygon` does. A placemark with several polygons has several.
        public var shapes: [GeoPolygon]
        public var start: Date?
        public var end: Date?
        public var satellite: String?

        public func contains(_ point: Coordinate) -> Bool { shapes.contains { $0.contains(point) } }
    }

    /// Parses a KML file into placemarks, file order.
    public static func placemarks(from data: Data) throws -> [Placemark] {
        let delegate = KMLDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        guard parser.parse() else {
            throw SourceError.decoding("HMS KML: \(parser.parserError.map { String(describing: $0) } ?? "unreadable XML")")
        }
        if let e = delegate.failure { throw e }
        return delegate.placemarks
    }

    /// The analysis for a point: the densest placemark containing it; `validFrom`/`validTo` span the placemarks of that
    /// density that contain the point. `polygonCount` is the number of placemarks in the file.
    public static func analysis(of placemarks: [Placemark], at point: Coordinate, day: Date) -> SmokeAnalysis {
        let containing = placemarks.filter { $0.contains(point) }
        guard let densest = containing.map(\.density).max() else {
            return SmokeAnalysis(density: .none, day: day, polygonCount: placemarks.count)
        }
        let same = containing.filter { $0.density == densest }
        return SmokeAnalysis(density: densest, day: day, polygonCount: placemarks.count,
                             validFrom: same.compactMap(\.start).min(), validTo: same.compactMap(\.end).max())
    }

    /// `2025227 1200UTC` (year, day of year, HHmm) as a UTC date; nil when it does not have that form.
    public static func parseTime(_ text: String) -> Date? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count == 2, parts[0].count == 7, parts[1].hasSuffix("UTC"), parts[1].count == 7,
              let year = Int(parts[0].prefix(4)), let doy = Int(parts[0].suffix(3)), (1...366).contains(doy),
              let hhmm = Int(parts[1].prefix(4)) else { return nil }
        let hour = hhmm / 100, minute = hhmm % 100
        guard hour < 24, minute < 60 else { return nil }
        let days = SWPCUTC.daysFromCivil(year: year, month: 1, day: 1) + doy - 1
        return Date(timeIntervalSince1970: TimeInterval(days * 86_400 + hour * 3600 + minute * 60))
    }

    /// The URL of the KML for a UTC day.
    public static func fileURL(forDay day: Date) -> URL {
        let c = civilDay(of: day)
        let ymd = String(format: "%04d%02d%02d", c.year, c.month, c.day)
        let path = String(format: "%04d/%02d", c.year, c.month)
        return URL(string: "https://satepsanone.nesdis.noaa.gov/pub/FIRE/web/HMS/Smoke_Polygons/KML/\(path)/hms_smoke\(ymd).kml")!
    }

    /// UTC midnight of the day containing `date`.
    public static func utcDay(of date: Date) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 86_400).rounded(.down) * 86_400)
    }

    static func civilDay(of date: Date) -> (year: Int, month: Int, day: Int) {
        SWPCUTC.civil(fromDays: Int((date.timeIntervalSince1970 / 86_400).rounded(.down)))
    }

    /// `lon,lat[,alt]` tuples separated by whitespace.
    static func ring(from text: String) -> [Coordinate]? {
        var out: [Coordinate] = []
        for token in text.split(whereSeparator: { $0.isWhitespace }) {
            let f = token.split(separator: ",")
            guard f.count >= 2, let lon = Double(f[0]), let lat = Double(f[1]),
                  abs(lat) <= 90, abs(lon) <= 360 else { return nil }
            out.append(Coordinate(latitude: lat, longitude: lon))
        }
        return out
    }

    private final class KMLDelegate: NSObject, XMLParserDelegate {
        var placemarks: [Placemark] = []
        var failure: SourceError?

        private var path: [String] = []
        private var text = ""
        private var folderNames: [String] = []
        // Current placemark.
        private var inPlacemark = false
        private var descriptionText = ""
        private var shapes: [GeoPolygon] = []
        private var rings: [[Coordinate]] = []

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                    attributes: [String: String] = [:]) {
            path.append(name)
            text = ""
            switch name {
            case "Folder": folderNames.append("")
            case "Placemark": inPlacemark = true; descriptionText = ""; shapes = []; rings = []
            case "Polygon": rings = []
            default: break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }
        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) { text += String(decoding: CDATABlock, as: UTF8.self) }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            defer { path.removeLast(); text = "" }
            let parent = path.count >= 2 ? path[path.count - 2] : ""
            switch name {
            case "name" where parent == "Folder":
                if !folderNames.isEmpty { folderNames[folderNames.count - 1] = text.trimmingCharacters(in: .whitespacesAndNewlines) }
            case "description" where parent == "Placemark":
                descriptionText = text
            case "coordinates" where inPlacemark:
                guard let r = HMSMapping.ring(from: text) else {
                    failure = failure ?? .decoding("HMS KML: bad coordinates in a placemark")
                    return
                }
                rings.append(r)
            case "Polygon" where inPlacemark:
                let polygon = GeoPolygon(rings: rings)
                if !polygon.isEmpty { shapes.append(polygon) }
                rings = []
            case "Folder":
                if !folderNames.isEmpty { folderNames.removeLast() }
            case "Placemark":
                inPlacemark = false
                finishPlacemark()
            default: break
            }
        }

        private func finishPlacemark() {
            var fields: [String: String] = [:]
            for line in descriptionText.replacingOccurrences(of: "<br>", with: "\n").split(whereSeparator: \.isNewline) {
                // Strip any wrapping tag such as <div ...> before the first field and </div> after the last.
                var s = String(line)
                while let open = s.range(of: "<"), let close = s.range(of: ">", range: open.lowerBound..<s.endIndex) {
                    s.removeSubrange(open.lowerBound..<close.upperBound)
                }
                guard let colon = s.firstIndex(of: ":") else { continue }
                let key = s[..<colon].trimmingCharacters(in: .whitespaces)
                fields[key] = s[s.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            }
            let folder = folderNames.last ?? ""
            let density = Self.density(fields["Density"]) ?? Self.density(folder)
            guard let density else {
                failure = failure ?? .decoding("HMS KML: placemark without a density (folder '\(folder)')")
                return
            }
            placemarks.append(Placemark(density: density, shapes: shapes, start: fields["Start Time"].flatMap(HMSMapping.parseTime),
                                        end: fields["End Time"].flatMap(HMSMapping.parseTime), satellite: fields["Satellite"]))
        }

        private static func density(_ text: String?) -> SmokeAnalysis.Density? {
            guard let t = text?.lowercased() else { return nil }
            if t.contains("heavy") { return .heavy }
            if t.contains("medium") { return .medium }
            if t.contains("light") { return .light }
            return nil
        }
    }
}
