import Foundation
import IterModel
import IterSources

/// Wikimedia Commons responses into licensed photos. Pure.
public enum CommonsMapping {
    /// Files returned by a plain `list=geosearch` (titles and coordinates only), nearest first.
    public struct GeoFile: Hashable, Sendable {
        public var pageID: Int
        public var title: String
        public var coordinate: Coordinate?
        public var distanceM: Double?
    }

    public static func geosearch(from data: Data) throws -> [GeoFile] {
        let object = try WikipediaMapping.jsonObject(data)
        if let err = WikimediaAPI.errorText(in: object) { throw SourceError.http(status: 200, excerpt: "commons: \(err)") }
        guard let query = object["query"] as? [String: Any], let rows = query["geosearch"] as? [[String: Any]] else { return [] }
        return rows.compactMap { row in
            guard let id = (row["pageid"] as? NSNumber)?.intValue, let title = row["title"] as? String else { return nil }
            var c: Coordinate?
            if let lat = (row["lat"] as? NSNumber)?.doubleValue, let lon = (row["lon"] as? NSNumber)?.doubleValue {
                c = Coordinate(latitude: lat, longitude: lon)
            }
            return GeoFile(pageID: id, title: title, coordinate: c, distanceM: (row["dist"] as? NSNumber)?.doubleValue)
        }
    }

    /// A cheap photo-density count from a plain geosearch response.
    public static func density(from data: Data) throws -> Int { try geosearch(from: data).count }

    /// The result of mapping an imageinfo response.
    public struct Result: Hashable, Sendable {
        /// Files the response held, free or not (the density figure).
        public var filesFound: Int
        /// Files with a recognised free licence, in the API's `index` order.
        public var photos: [LicensedPhoto]
    }

    /// Maps a `generator=geosearch` + `prop=imageinfo` response. Files whose licence is missing, non-free or
    /// unrecognised are skipped: an unlicensed photo is never returned.
    public static func photos(from data: Data) throws -> Result {
        let object = try WikipediaMapping.jsonObject(data)
        if let err = WikimediaAPI.errorText(in: object) { throw SourceError.http(status: 200, excerpt: "commons: \(err)") }
        guard let query = object["query"] as? [String: Any] else { return Result(filesFound: 0, photos: []) }
        var pages: [[String: Any]] = []
        if let dict = query["pages"] as? [String: Any] { pages = dict.values.compactMap { $0 as? [String: Any] } }
        else if let list = query["pages"] as? [[String: Any]] { pages = list }
        pages.sort {
            let a = ($0["index"] as? NSNumber)?.intValue ?? Int.max, b = ($1["index"] as? NSNumber)?.intValue ?? Int.max
            return a != b ? a < b : (($0["pageid"] as? NSNumber)?.intValue ?? 0) < (($1["pageid"] as? NSNumber)?.intValue ?? 0)
        }
        return Result(filesFound: pages.count, photos: pages.compactMap(photo))
    }

    static func photo(_ page: [String: Any]) -> LicensedPhoto? {
        guard let info = (page["imageinfo"] as? [[String: Any]])?.first,
              let meta = info["extmetadata"] as? [String: Any] else { return nil }
        func value(_ key: String) -> String? {
            let v = (meta[key] as? [String: Any])?["value"]
            if let s = v as? String { return s }
            if let n = v as? NSNumber { return n.stringValue }
            return nil
        }
        guard let licence = value("LicenseShortName")?.trimmingCharacters(in: .whitespacesAndNewlines),
              isFree(licence: licence, nonFree: value("NonFree")) else { return nil }
        let rawTitle = (page["title"] as? String) ?? value("ObjectName") ?? ""
        let title = rawTitle.hasPrefix("File:") ? String(rawTitle.dropFirst(5)) : rawTitle
        let author = value("Artist").map(plainText).flatMap { $0.isEmpty ? nil : $0 }
        var coordinate: Coordinate?
        if let lat = value("GPSLatitude").flatMap(Double.init), let lon = value("GPSLongitude").flatMap(Double.init) {
            coordinate = Coordinate(latitude: lat, longitude: lon)
        }
        func url(_ s: Any?) -> URL? { (s as? String).flatMap { URL(string: $0) } }
        func int(_ s: Any?) -> Int? { (s as? NSNumber)?.intValue }
        let credit = "Photo: " + (author ?? "unknown author") + ", \(licence), via Wikimedia Commons"
        return LicensedPhoto(
            title: title, coordinate: coordinate, imageURL: url(info["url"]), thumbnailURL: url(info["thumburl"]),
            pageURL: url(info["descriptionurl"]), licenceName: licence,
            licenceURL: value("LicenseUrl").flatMap { URL(string: $0.trimmingCharacters(in: .whitespaces)) },
            author: author, credit: credit, width: int(info["width"]), height: int(info["height"]))
    }

    /// True for a licence name that is recognisably free. Anything else (fair use, unknown, empty) is not.
    static func isFree(licence: String, nonFree: String?) -> Bool {
        let l = licence.lowercased()
        guard !l.isEmpty else { return false }
        if let nonFree, ["true", "1", "yes"].contains(nonFree.lowercased()) { return false }
        if ["fair use", "non-free", "nonfree", "all rights reserved", "copyrighted"].contains(where: l.contains),
           !l.hasPrefix("copyrighted free use") { return false }
        // Non-commercial and no-derivatives Creative Commons terms are not free licences.
        let tokens = Set(l.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
        if tokens.contains("nc") || tokens.contains("nd") { return false }
        let firstTokens: Set<String> = ["cc", "cc0", "pd", "gfdl", "fal", "ogl", "mit", "bsd", "gpl", "lgpl", "attribution"]
        let phrases = ["public domain", "free art", "open government", "copyrighted free use", "no restrictions"]
        if let first = l.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).first, firstTokens.contains(String(first)) {
            return true
        }
        return phrases.contains { l.hasPrefix($0) }
    }

    /// HTML to plain text: tags dropped, entities decoded, whitespace collapsed.
    static func plainText(_ html: String) -> String {
        var out = ""
        var inTag = false
        for ch in html {
            if ch == "<" { inTag = true; out.append(" ") } else if ch == ">" && inTag { inTag = false } else if !inTag { out.append(ch) }
        }
        out = decodeEntities(out)
        return out.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    private static let named = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " "]

    static func decodeEntities(_ s: String) -> String {
        guard s.contains("&") else { return s }
        var out = ""
        var i = s.startIndex
        while i < s.endIndex {
            if s[i] == "&", let semi = s[i...].prefix(10).firstIndex(of: ";") {
                let body = String(s[s.index(after: i)..<semi])
                var decoded: String?
                if body.hasPrefix("#x") || body.hasPrefix("#X") {
                    decoded = UInt32(body.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
                } else if body.hasPrefix("#") {
                    decoded = UInt32(body.dropFirst()).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
                } else { decoded = named[body] }
                if let decoded { out += decoded; i = s.index(after: semi); continue }
            }
            out.append(s[i])
            i = s.index(after: i)
        }
        return out
    }
}
