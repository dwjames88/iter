// MGRS.swift
//
// Military Grid Reference System on WGS84 (NGA / STANAG 2211 lettering, as in NGA GEOTRANS):
//  - UTM part: zone (1-60), latitude band C-X (8 degrees tall, X is 12 degrees: 72 N to 84 N; I and O
//    unused), 100 km square letters: column letters run A-H, J-R, S-Z by zone (zone - 1) mod 3, row
//    letters A-V (no I, O) cycle every 2,000 km, offset by 5 letters (start at F) in even zones.
//  - Polar part (UPS, beyond 84 N / 80 S): letter A (south, west), B (south, east), Y (north, west),
//    Z (north, east), then column and row letters as GEOTRANS: column letters J K L P Q R S T U X Y Z
//    west of the pole's meridian line (easting < 2,000 km, from 800 km), A B C F G H J K L P Q R east
//    (from 2,000 km); row letters A-Z without I and O, from 800 km (south) or 1,300 km (north).
//  - Precision: 0 to 5 digit pairs, i.e. 100 km down to 1 m. Coordinates are TRUNCATED (not rounded) to
//    the precision, so a reference names the grid cell containing the point.
//
// Inverse: returns the south-west corner of the cell (plus its centre and size). The 2,000 km
// row-letter cycle is resolved with the latitude band: the cell chosen is the first one at or above the
// band's southern edge (its northing floored to 100 km).
//
// Pure, Foundation only, no networking.

import Foundation

public struct MGRSReference: Sendable, Equatable, CustomStringConvertible {
    /// UTM zone 1...60, or 0 for the polar (UPS) regions.
    public var zone: Int
    /// Latitude band C...X for UTM; A, B, Y or Z for the polar regions.
    public var band: Character
    public var columnLetter: Character
    public var rowLetter: Character
    /// Metres within the 100 km square, already truncated to `precision` digits.
    public var easting: Int
    public var northing: Int
    /// Digits per coordinate, 0 (100 km) ... 5 (1 m).
    public var precision: Int

    public init(zone: Int, band: Character, columnLetter: Character, rowLetter: Character,
                easting: Int, northing: Int, precision: Int) {
        self.zone = zone; self.band = band; self.columnLetter = columnLetter; self.rowLetter = rowLetter
        self.easting = easting; self.northing = northing; self.precision = precision
    }

    public var isPolar: Bool { zone == 0 }

    /// Compact form, `18SUJ2338507460` (zone not zero-padded, as GeographicLib and Wikipedia write it).
    public var description: String { formatted(spaced: false) }

    /// With spaces: `18S UJ 23385 07460`.
    /// `padZone` writes zones 1-9 as `01`-`09` (NGA GEOTRANS style); parsing accepts both.
    public func formatted(spaced: Bool, padZone: Bool = false) -> String {
        let sep = spaced ? " " : ""
        let zoneText = padZone && zone < 10 ? "0\(zone)" : "\(zone)"
        var s = isPolar ? String(band) : "\(zoneText)\(band)"
        s += sep + String(columnLetter) + String(rowLetter)
        if precision > 0 {
            let divisor = Int(pow(10.0, Double(5 - precision)))
            let e = String(easting / divisor), n = String(northing / divisor)
            s += sep + String(repeating: "0", count: precision - e.count) + e
            s += sep + String(repeating: "0", count: precision - n.count) + n
        }
        return s
    }
}

/// A decoded MGRS reference.
public struct MGRSLocation: Sendable, Equatable {
    /// South-west corner of the cell, degrees.
    public var latitude: Double
    public var longitude: Double
    /// Centre of the cell, degrees.
    public var centreLatitude: Double
    public var centreLongitude: Double
    /// Digits per coordinate and the matching cell edge in metres (1 m ... 100,000 m).
    public var precision: Int
    public var cellSizeMetres: Double
    /// UTM/UPS coordinate of the south-west corner.
    public var utm: UTMUPSCoordinate
}

public enum MGRS {
    static let bandLetters = Array("CDEFGHJKLMNPQRSTUVWX")
    static let rowLetters = Array("ABCDEFGHJKLMNPQRSTUV")
    static let columnSets = [Array("ABCDEFGH"), Array("JKLMNPQR"), Array("STUVWXYZ")]
    // UPS lettering (GEOTRANS).
    static let upsWestColumns = Array("JKLPQRSTUXYZ")
    static let upsEastColumns = Array("ABCFGHJKLPQR")
    static let upsRows = Array("ABCDEFGHJKLMNPQRSTUVWXYZ")

    // MARK: Forward

    /// Converts a latitude/longitude to an MGRS reference, truncated to `precision` digits per coordinate.
    public static func forward(latitude: Double, longitude: Double, precision: Int = 5) throws -> MGRSReference {
        guard (0...5).contains(precision) else { throw MGRSError.invalidPrecision }
        guard latitude.isFinite, abs(latitude) <= 90 else { throw MGRSError.invalidLatitude }
        guard longitude.isFinite else { throw MGRSError.invalidLongitude }
        if latitude >= UTM.minimumLatitude && latitude <= UTM.maximumLatitude {
            let utm = try UTM.forward(latitude: latitude, longitude: longitude)
            let bandIndex = min(Int(floor((latitude + 80) / 8)), 19)
            return try reference(from: utm, band: bandLetters[bandIndex], precision: precision)
        }
        let ups = try UPS.forward(latitude: latitude, longitude: longitude)
        let letter: Character = ups.isNorth ? (ups.easting < 2_000_000 ? "Y" : "Z")
                                            : (ups.easting < 2_000_000 ? "A" : "B")
        return try reference(from: ups, band: letter, precision: precision)
    }

    /// Convenience returning the string.
    public static func string(latitude: Double, longitude: Double, precision: Int = 5, spaced: Bool = false,
                              padZone: Bool = false) throws -> String {
        try forward(latitude: latitude, longitude: longitude, precision: precision)
            .formatted(spaced: spaced, padZone: padZone)
    }

    /// Builds a reference from a UTM/UPS coordinate and its band (or polar) letter.
    static func reference(from c: UTMUPSCoordinate, band: Character, precision: Int) throws -> MGRSReference {
        guard (0...5).contains(precision) else { throw MGRSError.invalidPrecision }
        let e = c.easting, n = c.northing
        let eIdx = Int(floor(e / 100_000)), nIdx = Int(floor(n / 100_000))
        let eRem = Int(floor(e - Double(eIdx) * 100_000)), nRem = Int(floor(n - Double(nIdx) * 100_000))
        let divisor = Int(pow(10.0, Double(5 - precision)))
        let col: Character, row: Character
        if c.isPolar {
            let west = e < 2_000_000
            let ci = eIdx - (west ? 8 : 20), ri = nIdx - (c.isNorth ? 13 : 8)
            let cols = west ? upsWestColumns : upsEastColumns
            guard cols.indices.contains(ci), upsRows.indices.contains(ri) else { throw MGRSError.invalidCoordinate }
            col = cols[ci]; row = upsRows[ri]
        } else {
            let set = columnSets[(c.zone - 1) % 3]
            guard set.indices.contains(eIdx - 1), nIdx >= 0 else { throw MGRSError.invalidCoordinate }
            col = set[eIdx - 1]
            row = rowLetters[(nIdx + (c.zone % 2 == 0 ? 5 : 0)) % 20]
        }
        return MGRSReference(zone: c.zone, band: band, columnLetter: col, rowLetter: row,
                             easting: eRem / divisor * divisor, northing: nRem / divisor * divisor,
                             precision: precision)
    }

    // MARK: Parse

    /// Parses MGRS text: spaces optional, case-insensitive. Examples: `18SUJ2338507460`, `18s uj 23385 07460`,
    /// `33UXP04`; polar references are `A`, `B`, `Y` or `Z` followed by two square letters (`YJK1234512345`).
    public static func parse(_ text: String) throws -> MGRSReference {
        let chars = Array(text.uppercased().filter { !$0.isWhitespace })
        func bad(_ why: String) -> MGRSError { .invalidReference("\(why): \(text)") }
        var i = 0
        var zone = 0
        let band: Character
        while i < chars.count, i < 2, chars[i].isASCII, chars[i].isNumber { zone = zone * 10 + Int(String(chars[i]))!; i += 1 }
        if i == 0 {
            guard let first = chars.first, "ABYZ".contains(first) else { throw bad("missing zone or polar letter") }
            band = first; i = 1
        } else {
            guard (1...60).contains(zone) else { throw bad("zone out of range") }
            guard i < chars.count, bandLetters.contains(chars[i]) else { throw bad("bad latitude band") }
            band = chars[i]; i += 1
        }
        guard i + 2 <= chars.count else { throw bad("missing square letters") }
        let col = chars[i], row = chars[i + 1]; i += 2
        let digits = Array(chars[i...])
        guard digits.allSatisfy({ $0.isASCII && $0.isNumber }) else { throw bad("unexpected characters") }
        guard digits.count % 2 == 0, digits.count <= 10 else { throw bad("digits must come in pairs, at most 5 each") }
        if zone == 0 {
            let west = "AY".contains(band)
            guard (west ? upsWestColumns : upsEastColumns).contains(col), upsRows.contains(row) else { throw bad("bad square letters") }
            // North letters must be consistent with rows (north rows end at P).
            if "YZ".contains(band), let ri = upsRows.firstIndex(of: row), ri > 13 { throw bad("row outside the north polar grid") }
        } else {
            guard columnSets[(zone - 1) % 3].contains(col), rowLetters.contains(row) else { throw bad("bad square letters") }
        }
        let p = digits.count / 2
        let divisor = Int(pow(10.0, Double(5 - p)))
        let e = p == 0 ? 0 : Int(String(digits[0..<p]))! * divisor
        let n = p == 0 ? 0 : Int(String(digits[p...]))! * divisor
        return MGRSReference(zone: zone, band: band, columnLetter: col, rowLetter: row,
                             easting: e, northing: n, precision: p)
    }

    // MARK: Inverse

    /// Decodes text (see `parse`).
    public static func decode(_ text: String) throws -> MGRSLocation { try decode(parse(text)) }

    /// Decodes a reference to its south-west corner (and the cell centre).
    public static func decode(_ ref: MGRSReference) throws -> MGRSLocation {
        let cell = Double(Int(pow(10.0, Double(5 - ref.precision))))
        let sw = try utmupsCorner(of: ref)
        let (lat, lon) = try inverse(sw)
        var mid = sw
        mid.easting += cell / 2; mid.northing += cell / 2
        let (clat, clon) = try inverse(mid)
        return MGRSLocation(latitude: lat, longitude: lon, centreLatitude: clat, centreLongitude: clon,
                            precision: ref.precision, cellSizeMetres: cell, utm: sw)
    }

    private static func inverse(_ c: UTMUPSCoordinate) throws -> (Double, Double) {
        c.isPolar ? try UPS.inverse(c) : try UTM.inverse(c)
    }

    /// The UTM/UPS coordinate of the south-west corner of the referenced cell.
    static func utmupsCorner(of ref: MGRSReference) throws -> UTMUPSCoordinate {
        if ref.isPolar {
            let west = "AY".contains(ref.band)
            let north = "YZ".contains(ref.band)
            let cols = west ? upsWestColumns : upsEastColumns
            guard let ci = cols.firstIndex(of: ref.columnLetter), let ri = upsRows.firstIndex(of: ref.rowLetter),
                  ["A", "B", "Y", "Z"].contains(ref.band) else { throw MGRSError.invalidReference(ref.description) }
            if north && ri > 13 { throw MGRSError.invalidReference(ref.description) }
            let e = Double((west ? 8 : 20) + ci) * 100_000 + Double(ref.easting)
            let n = Double((north ? 13 : 8) + ri) * 100_000 + Double(ref.northing)
            return UTMUPSCoordinate(zone: 0, isNorth: north, easting: e, northing: n)
        }
        guard (1...60).contains(ref.zone), let bandIndex = bandLetters.firstIndex(of: ref.band),
              let ci = columnSets[(ref.zone - 1) % 3].firstIndex(of: ref.columnLetter),
              let rowIndex = rowLetters.firstIndex(of: ref.rowLetter) else {
            throw MGRSError.invalidReference(ref.description)
        }
        let north = bandIndex >= 10 // bands N...X
        let easting = Double(ci + 1) * 100_000 + Double(ref.easting)
        let rowInCycle = (rowIndex - (ref.zone % 2 == 0 ? 5 : 0) + 20) % 20
        let n0 = Double(rowInCycle) * 100_000 + Double(ref.northing)

        // Minimum northing of the band over the zone, from its southern edge at the central meridian and
        // 6 degrees either side (a safe lower bound); the cell's 100 km row may start slightly below it.
        let southLat = -80 + 8 * Double(bandIndex)
        var minNorthing = Double.infinity
        for d in [-6.0, 0, 6.0] {
            let lam = d * .pi / 180
            let y = TransverseMercator.utm.forward(phi: southLat * .pi / 180, lambda: lam).y
            minNorthing = min(minNorthing, y + (southLat < 0 ? 10_000_000 : 0))
        }
        let base = floor(minNorthing / 100_000) * 100_000
        var northing = n0
        while northing < base { northing += 2_000_000 }
        return UTMUPSCoordinate(zone: ref.zone, isNorth: north, easting: easting, northing: northing)
    }
}
