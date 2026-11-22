// Tests for UTM, UPS and MGRS.
//
// Published reference values: the EXAMPLES section of the GeographicLib GeoConvert man page
// (https://geographiclib.sourceforge.io/C++/doc/GeoConvert.1.html):
//   echo 38SMB4488 | GeoConvert        => 33.33424 44.40363        (GeoConvert returns the cell centre)
//   echo 38SMB4488 | GeoConvert -u     => 38n 444500 3688500
//   echo E44d24 N33d20 | GeoConvert -m -p -3 => 38SMB4488
// Independent cross-check: Fixtures/Geomag/mgrs-reference.json, generated with the `mgrs` package
// (NGA GEOTRANS C code) and `pyproj` (PROJ), see the "generator" field in that file.

import Foundation
import Testing
@testable import IterSourcesLive

private struct ReferencePoint: Decodable, Sendable {
    var name: String
    var lat: Double
    var lon: Double
    var zone: Int
    var north: Bool
    var easting: Double
    var northing: Double
    var mgrs: String
    var swLatLon: [Double]
}

private struct ReferenceFile: Decodable, Sendable {
    var generator: String
    var points: [ReferencePoint]
}

private func loadReference() throws -> [ReferencePoint] {
    guard let base = Bundle.module.resourceURL else { throw CocoaError(.fileNoSuchFile) }
    let data = try Data(contentsOf: base.appendingPathComponent("Fixtures/Geomag/mgrs-reference.json"))
    return try JSONDecoder().decode(ReferenceFile.self, from: data).points
}

/// Approximate ground distance in metres between two nearby points.
private func metres(_ a: (Double, Double), _ b: (Double, Double)) -> Double {
    let dLat = (a.0 - b.0) * 111_320
    var dLon = a.1 - b.1
    if dLon > 180 { dLon -= 360 } else if dLon < -180 { dLon += 360 }
    return (dLat * dLat + pow(dLon * 111_320 * cos(a.0 * .pi / 180), 2)).squareRoot()
}

@Suite("MGRS and UTM/UPS")
struct MGRSTests {
    // MARK: Published examples

    @Test func geoConvertManPageExamples() throws {
        let loc = try MGRS.decode("38SMB4488")
        // 5 decimals published, so half a unit in the last place.
        #expect(abs(loc.centreLatitude - 33.33424) < 6e-6)
        #expect(abs(loc.centreLongitude - 44.40363) < 6e-6)
        // "38n 444500 3688500" is the centre; the south-west corner is 500 m less in each.
        #expect(loc.utm.zone == 38 && loc.utm.isNorth)
        #expect(loc.utm.easting == 444_000 && loc.utm.northing == 3_688_000)
        #expect(loc.precision == 2 && loc.cellSizeMetres == 1000)
        // E44d24 N33d20 = 44.4 E, 33.333... N at 1 km precision.
        #expect(try MGRS.string(latitude: 33 + 20.0 / 60, longitude: 44.4, precision: 2) == "38SMB4488")
        let utm = try UTM.forward(latitude: loc.centreLatitude, longitude: loc.centreLongitude)
        #expect(abs(utm.easting - 444_500) < 0.5 && abs(utm.northing - 3_688_500) < 0.5)
    }

    // MARK: Zones

    @Test func zoneRules() {
        #expect(UTM.zone(latitude: 0, longitude: -180) == 1)
        #expect(UTM.zone(latitude: 0, longitude: 180) == 1) // antimeridian is -180, as in GEOTRANS
        #expect(UTM.zone(latitude: 0, longitude: 179.9999) == 60)
        #expect(UTM.zone(latitude: 0, longitude: 0) == 31)
        #expect(UTM.zone(latitude: 0, longitude: 6) == 32)
        // Norway: 56 N to 64 N, 3 E to 12 E is zone 32.
        #expect(UTM.zone(latitude: 60, longitude: 3) == 32)
        #expect(UTM.zone(latitude: 60, longitude: 11.9999) == 32)
        #expect(UTM.zone(latitude: 60, longitude: 12) == 33)
        #expect(UTM.zone(latitude: 60, longitude: 2.9999) == 31)
        #expect(UTM.zone(latitude: 55.9999, longitude: 5) == 31)
        #expect(UTM.zone(latitude: 64, longitude: 5) == 31)
        // Svalbard: 31X 33X 35X 37X.
        #expect(UTM.zone(latitude: 78, longitude: 5) == 31)
        #expect(UTM.zone(latitude: 78, longitude: 8.9999) == 31)
        #expect(UTM.zone(latitude: 78, longitude: 9) == 33)
        #expect(UTM.zone(latitude: 78, longitude: 21) == 35)
        #expect(UTM.zone(latitude: 78, longitude: 33) == 37)
        #expect(UTM.zone(latitude: 78, longitude: 42) == 38)
        #expect(UTM.zone(latitude: 71.9999, longitude: 15) == 33)
        #expect(UTM.zone(latitude: 71.9999, longitude: 7) == 32) // below 72 N the standard grid applies
        #expect(UTM.zone(latitude: 72, longitude: 7) == 31)
        #expect(UTM.zone(latitude: 72, longitude: 10) == 33)
        #expect(UTM.zone(latitude: -78, longitude: 15) == 33) // south is regular
    }

    @Test func utmCoverageAndPrecisionErrors() {
        #expect(throws: MGRSError.outsideUTMCoverage) { try UTM.forward(latitude: 84.1, longitude: 0) }
        #expect(throws: MGRSError.outsideUTMCoverage) { try UTM.forward(latitude: -80.1, longitude: 0) }
        #expect(throws: MGRSError.invalidLatitude) { try UTM.forward(latitude: 91, longitude: 0) }
        #expect(throws: MGRSError.invalidPrecision) { try MGRS.forward(latitude: 0, longitude: 0, precision: 6) }
        #expect(throws: MGRSError.invalidLongitude) { try MGRS.forward(latitude: 0, longitude: .nan) }
    }

    // MARK: Projection accuracy

    /// Round trip through the Kruger series across a zone's width and latitudes: sub-millimetre.
    @Test func utmRoundTripSubMillimetre() throws {
        var worst = 0.0
        for lat in stride(from: -80.0, through: 84.0, by: 4.0) {
            for dLon in stride(from: -3.0, through: 3.0, by: 0.5) {
                let lon = 15 + dLon // zone 33 central meridian 15
                if lat >= 72 && lon >= 9 && lon < 21 || lat < 72 {
                    let c = try UTM.forward(latitude: lat, longitude: lon, zone: 33)
                    let back = try UTM.inverse(c)
                    let err = metres((lat, lon), (back.latitude, back.longitude))
                    worst = max(worst, err)
                }
            }
        }
        print("UTM round trip max error m: \(worst)")
        #expect(worst < 1e-3)
    }

    // MARK: Cross-check against NGA GEOTRANS (mgrs) and PROJ (pyproj)

    @Test func forwardAgainstReference() throws {
        let points = try loadReference()
        #expect(points.count >= 150)
        var maxDelta = 0.0
        var mismatches: [String] = []
        for p in points {
            let ref = try MGRS.forward(latitude: p.lat, longitude: p.lon, precision: 5)
            // Easting/northing against PROJ within 1 mm.
            let c = p.zone == 0 ? try UPS.forward(latitude: p.lat, longitude: p.lon)
                                : try UTM.forward(latitude: p.lat, longitude: p.lon)
            #expect(c.zone == p.zone && c.isNorth == p.north, "\(p.name) zone/hemisphere")
            let dE = abs(c.easting - p.easting), dN = abs(c.northing - p.northing)
            maxDelta = max(maxDelta, dE, dN)
            #expect(dE < 0.001 && dN < 0.001, "\(p.name): dE \(dE) dN \(dN)")
            // Exact string at 1 m.
            // GEOTRANS zero-pads zones 1-9; we compare against the padded form.
            if ref.formatted(spaced: false, padZone: true) != p.mgrs { mismatches.append("\(p.name): got \(ref) want \(p.mgrs)") }
        }
        print("UTM/UPS forward max |dE|,|dN| vs PROJ (m): \(maxDelta)")
        print("MGRS string mismatches: \(mismatches)")
        #expect(mismatches.isEmpty, "\(mismatches)")
    }

    @Test func inverseAgainstReference() throws {
        let points = try loadReference()
        var worst = 0.0
        var worstName = ""
        for p in points {
            let loc = try MGRS.decode(p.mgrs)
            let d = metres((p.swLatLon[0], p.swLatLon[1]), (loc.latitude, loc.longitude))
            if d > worst { worst = d; worstName = p.name }
            #expect(d < 1.0, "\(p.name) \(p.mgrs): \(d) m")
            // The original point lies inside the 1 m cell, so within 1.5 m of the SW corner.
            let back = metres((p.lat, p.lon), (loc.latitude, loc.longitude))
            #expect(back < 1.5, "\(p.name) point is \(back) m from decoded corner")
        }
        print("MGRS inverse max distance to GEOTRANS corner (m): \(worst) at \(worstName)")
    }

    @Test func randomRoundTripThroughEveryPrecision() throws {
        var rng = SplitMix(seed: 42)
        for _ in 0..<400 {
            let lat = Double.random(in: -90...90, using: &rng)
            let lon = Double.random(in: -180...180, using: &rng)
            for p in 0...5 {
                let ref = try MGRS.forward(latitude: lat, longitude: lon, precision: p)
                let loc = try MGRS.decode(ref)
                #expect(loc.precision == p)
                // The cell (truncated) must contain the point: the point is within one cell diagonal of the corner.
                let d = metres((lat, lon), (loc.latitude, loc.longitude))
                #expect(d <= loc.cellSizeMetres * 1.5 + 0.01, "\(lat),\(lon) p\(p) \(ref): \(d)")
                // Parsing the formatted text gives the same reference (spaced and compact).
                #expect(try MGRS.parse(ref.formatted(spaced: true)) == ref)
                #expect(try MGRS.parse(ref.description.lowercased()) == ref)
            }
        }
    }

    // MARK: Formatting and parsing

    @Test func formattingAndParsing() throws {
        let ref = try MGRS.forward(latitude: 33 + 20.0 / 60, longitude: 44.4, precision: 5)
        #expect(try MGRS.parse("04QFJ12345678") == MGRS.parse("4QFJ12345678"))
        #expect(try MGRS.parse("4QFJ12345678").formatted(spaced: true, padZone: true) == "04Q FJ 1234 5678")
        #expect(ref.zone == 38 && ref.band == "S" && ref.columnLetter == "M" && ref.rowLetter == "B")
        #expect(ref.description.hasPrefix("38SMB44"))
        #expect(ref.formatted(spaced: true).hasPrefix("38S MB 44"))
        for text in ["38SMB4488", "38S MB 44 88", "38smb4488", " 38s mb 44 88 "] {
            let r = try MGRS.parse(text)
            #expect(r.zone == 38 && r.precision == 2 && r.easting == 44_000 && r.northing == 88_000)
            #expect(r.formatted(spaced: false) == "38SMB4488")
        }
        let zero = try MGRS.parse("38SMB")
        #expect(zero.precision == 0 && zero.formatted(spaced: true) == "38S MB")
        // Single-digit zone and leading zeros in the digits.
        let r = try MGRS.parse("4QFJ12345678")
        #expect(r.zone == 4 && r.easting == 12_340 && r.northing == 56_780 && r.precision == 4)
        #expect(try MGRS.parse("4QFJ0001000200").formatted(spaced: false) == "4QFJ0001000200")
        for bad in ["", "38S", "38SMB448", "38SMB44A8", "61SMB4488", "0SMB4488", "38IMB4488", "38SIB4488",
                    "38SMO4488", "38SMB123456789012", "38SAB4488", "XYZ"] {
            #expect(throws: MGRSError.self) { try MGRS.parse(bad) }
        }
    }

    // MARK: Lettering, even-zone offset, band edges

    @Test func letteringSchemes() throws {
        // Odd zone: row letters start at A at northing 0; even zone: start at F.
        let odd = try MGRS.reference(from: UTMUPSCoordinate(zone: 31, isNorth: true, easting: 500_000, northing: 0), band: "N", precision: 5)
        let even = try MGRS.reference(from: UTMUPSCoordinate(zone: 32, isNorth: true, easting: 500_000, northing: 0), band: "N", precision: 5)
        #expect(odd.rowLetter == "A" && even.rowLetter == "F")
        // Column sets by zone: 1 -> A-H, 2 -> J-R, 3 -> S-Z, then repeat.
        for (zone, first) in [(1, "A"), (2, "J"), (3, "S"), (4, "A")] {
            let r = try MGRS.reference(from: UTMUPSCoordinate(zone: zone, isNorth: true, easting: 100_000, northing: 0), band: "N", precision: 0)
            #expect(String(r.columnLetter) == first)
        }
        // The 2,000 km row cycle: northing 0 and 2,000,000 share a row letter; the band picks the right one.
        let low = try MGRS.decode("31NAA0000000000") // band N starts at the equator
        #expect(low.utm.northing == 0)
        let high = try MGRS.decode("31NAA0000000000".replacingOccurrences(of: "31N", with: "31Q")) // 8 N to 16 N: ~1.1e6..1.8e6
        #expect(high.utm.northing == 2_000_000)
    }

    @Test func bandsAtLatitudeEdges() throws {
        #expect(try MGRS.forward(latitude: -80, longitude: 0).band == "C")
        #expect(try MGRS.forward(latitude: -72, longitude: 0).band == "D")
        #expect(try MGRS.forward(latitude: -0.0001, longitude: 0).band == "M")
        #expect(try MGRS.forward(latitude: 0, longitude: 0).band == "N")
        #expect(try MGRS.forward(latitude: 72, longitude: 0).band == "X")
        #expect(try MGRS.forward(latitude: 84, longitude: 0).band == "X")
        #expect(try MGRS.forward(latitude: 84.0001, longitude: 10).band == "Z")
        #expect(try MGRS.forward(latitude: 84.0001, longitude: -10).band == "Y")
        #expect(try MGRS.forward(latitude: -80.0001, longitude: 10).band == "B")
        #expect(try MGRS.forward(latitude: -80.0001, longitude: -10).band == "A")
    }

    @Test func polesAreFinite() throws {
        for lat in [90.0, -90.0] {
            let r = try MGRS.forward(latitude: lat, longitude: 0)
            let loc = try MGRS.decode(r)
            #expect(abs(abs(loc.latitude) - 90) < 1e-4)
        }
    }
}

/// Small deterministic generator for reproducible random tests.
private struct SplitMix: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
