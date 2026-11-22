// Tests for WorldMagneticModel (WMM2025) against NOAA/NCEI's official test values.
//
// Fixtures (Fixtures/Geomag/), all from NCEI's WMM2025COF packages:
//  - WMM.COF: coefficients, 2025-01/WMM2025COF.zip.
//  - WMM2025_TEST_VALUES.txt: the 12 official test points (same zip), published precision
//    (components 0.1 nT, angles 0.01 degrees, rates 0.1 nT/yr and 0.01 degrees/yr).
//  - WMM2025_TestValues_100.txt: 100 further official points at full precision
//    (WMM2025_TestValues.txt in 2024-12/WMM2025COF.zip; no GV column, integer lat/lon).

import Foundation
import Testing
@testable import IterSourcesLive

private func geomagFixture(_ name: String) throws -> String {
    guard let base = Bundle.module.resourceURL else { throw CocoaError(.fileNoSuchFile) }
    let url = base.appendingPathComponent("Fixtures/Geomag/\(name)")
    return try String(contentsOf: url, encoding: .utf8)
}

private func dataRows(_ text: String) -> [[Double]] {
    text.split(whereSeparator: \.isNewline)
        .filter { !$0.hasPrefix("#") }
        .map { $0.split(whereSeparator: { $0 == " " || $0 == "\t" }).map { Double($0) ?? .nan } }
        .filter { !$0.isEmpty }
}

/// Tracks the largest absolute difference per quantity for the report.
private struct MaxDiff {
    var values: [String: Double] = [:]
    mutating func note(_ name: String, _ diff: Double) {
        values[name] = max(values[name] ?? 0, diff)
    }
    var summary: String {
        values.keys.sorted().map { "\($0)=\(String(format: "%.6f", values[$0]!))" }.joined(separator: " ")
    }
}

@Suite("WorldMagneticModel")
struct WorldMagneticModelTests {
    @Test func embeddedCoefficientsRoundTripToOfficialFile() throws {
        let official = try geomagFixture("WMM.COF")
        func tokens(_ s: String) -> [[String]] {
            s.split(whereSeparator: \.isNewline)
                .map { $0.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init) }
                .filter { !$0.isEmpty }
        }
        #expect(tokens(WMM2025Coefficients.cofText) == tokens(official))
        #expect(WorldMagneticModel.parsedRowCount == 90)
        #expect(WorldMagneticModel.epoch == 2025.0)
        #expect(WorldMagneticModel.name == "WMM-2025")
        #expect(WorldMagneticModel.releaseDate == "11/13/2024")
    }

    /// All 12 rows of the official WMM2025_TEST_VALUES.txt. Tolerance: half a unit of the last published
    /// digit plus slack for rounding of the published value: 0.06 nT, 0.06 nT/yr, 0.006 degrees,
    /// 0.006 degrees/yr. GV is NaN in the file for |lat| <= 55 and must be nil.
    @Test func officialTwelveTestValues() throws {
        let rows = dataRows(try geomagFixture("WMM2025_TEST_VALUES.txt"))
        #expect(rows.count == 12)
        var worst = MaxDiff()
        for r in rows {
            let (year, alt, lat, lon) = (r[0], r[1], r[2], r[3])
            let f = try WorldMagneticModel.evaluate(latitude: lat, longitude: lon, altitudeKm: alt, decimalYear: year)
            let label = "\(year) \(alt) \(lat) \(lon)"
            func check(_ name: String, _ got: Double, _ want: Double, _ tol: Double) {
                worst.note(name, abs(got - want))
                #expect(abs(got - want) <= tol, "\(label) \(name): got \(got) want \(want)")
            }
            check("X", f.north, r[4], 0.06); check("Y", f.east, r[5], 0.06); check("Z", f.down, r[6], 0.06)
            check("H", f.horizontal, r[7], 0.06); check("F", f.total, r[8], 0.06)
            check("I", f.inclination, r[9], 0.006); check("D", f.declination, r[10], 0.006)
            if r[11].isNaN {
                #expect(f.gridVariation == nil, "\(label) GV should be nil")
            } else {
                check("GV", f.gridVariation ?? .nan, r[11], 0.006)
            }
            check("dX", f.northRate, r[12], 0.06); check("dY", f.eastRate, r[13], 0.06)
            check("dZ", f.downRate, r[14], 0.06); check("dH", f.horizontalRate, r[15], 0.06)
            check("dF", f.totalRate, r[16], 0.06)
            check("dI", f.inclinationRate, r[17], 0.006); check("dD", f.declinationRate, r[18], 0.006)
        }
        print("WMM 12-point max diffs: \(worst.summary)")
    }

    /// All 100 rows of the official full-precision test file (including |lat| up to 89, altitudes to 94 km,
    /// years 2025 to 2029.5). Tolerances: 0.001 nT and 0.001 nT/yr for components, intensities and their
    /// rates; 0.006 degrees for D and I (published to 0.01); 0.0001 degrees/yr for the angle rates.
    @Test func officialHundredHighPrecisionValues() throws {
        let rows = dataRows(try geomagFixture("WMM2025_TestValues_100.txt"))
        #expect(rows.count == 100)
        var worst = MaxDiff()
        for r in rows {
            let (year, alt, lat, lon) = (r[0], r[1], r[2], r[3])
            let f = try WorldMagneticModel.evaluate(latitude: lat, longitude: lon, altitudeKm: alt, decimalYear: year)
            let label = "\(year) \(alt) \(lat) \(lon)"
            func check(_ name: String, _ got: Double, _ want: Double, _ tol: Double) {
                worst.note(name, abs(got - want))
                #expect(abs(got - want) <= tol, "\(label) \(name): got \(got) want \(want)")
            }
            check("D", f.declination, r[4], 0.006); check("I", f.inclination, r[5], 0.006)
            check("H", f.horizontal, r[6], 0.001); check("X", f.north, r[7], 0.001)
            check("Y", f.east, r[8], 0.001); check("Z", f.down, r[9], 0.001); check("F", f.total, r[10], 0.001)
            check("dD", f.declinationRate, r[11], 0.0001); check("dI", f.inclinationRate, r[12], 0.0001)
            check("dH", f.horizontalRate, r[13], 0.001); check("dX", f.northRate, r[14], 0.001)
            check("dY", f.eastRate, r[15], 0.001); check("dZ", f.downRate, r[16], 0.001)
            check("dF", f.totalRate, r[17], 0.001)
        }
        print("WMM 100-point max diffs: \(worst.summary)")
    }

    /// NOAA's live API (value in SOURCES.md): Whitney area 36.5785, -118.2923, 0 km, 2026-11-22 gives
    /// 11.81729 degrees; Sedrun area 46.5586, 8.5610 gives about 3.623. Tolerance 0.01 degrees.
    @Test func fieldPointsAgainstNOAAAPI() throws {
        let noon = try #require(ISO8601DateFormatter().date(from: "2026-11-22T00:00:00Z"))
        let w = try WorldMagneticModel.evaluate(latitude: 36.5785, longitude: -118.2923, altitudeKm: 0, date: noon)
        #expect(abs(w.declination - 11.817) < 0.01, "W declination \(w.declination)")
        let s = try WorldMagneticModel.evaluate(latitude: 46.5586, longitude: 8.5610, altitudeKm: 0, date: noon)
        #expect(abs(s.declination - 3.623) < 0.01, "S declination \(s.declination)")
        #expect(w.gridVariation == nil)
    }

    @Test func decimalYearFromDate() throws {
        let f = ISO8601DateFormatter()
        #expect(WorldMagneticModel.decimalYear(for: try #require(f.date(from: "2025-01-01T00:00:00Z"))) == 2025.0)
        // 2026 is not a leap year: 1 July 00:00 is day 181 of 365.
        let mid = WorldMagneticModel.decimalYear(for: try #require(f.date(from: "2026-07-01T00:00:00Z")))
        #expect(abs(mid - (2026 + 181.0 / 365.0)) < 1e-12)
        // Leap year: 2028-07-01 is day 182 of 366.
        let leap = WorldMagneticModel.decimalYear(for: try #require(f.date(from: "2028-07-01T00:00:00Z")))
        #expect(abs(leap - (2028 + 182.0 / 366.0)) < 1e-12)
    }

    @Test func validityWindowAndInputs() throws {
        #expect(throws: WorldMagneticModelError.outsideValidity(decimalYear: 2024.9)) {
            try WorldMagneticModel.evaluate(latitude: 0, longitude: 0, altitudeKm: 0, decimalYear: 2024.9)
        }
        #expect(throws: WorldMagneticModelError.outsideValidity(decimalYear: 2030.1)) {
            try WorldMagneticModel.evaluate(latitude: 0, longitude: 0, altitudeKm: 0, decimalYear: 2030.1)
        }
        _ = try WorldMagneticModel.evaluate(latitude: 0, longitude: 0, altitudeKm: 0, decimalYear: 2030.0)
        #expect(throws: WorldMagneticModelError.invalidInput) {
            try WorldMagneticModel.evaluate(latitude: 91, longitude: 0, altitudeKm: 0, decimalYear: 2026)
        }
        #expect(throws: WorldMagneticModelError.invalidInput) {
            try WorldMagneticModel.evaluate(latitude: .nan, longitude: 0, altitudeKm: 0, decimalYear: 2026)
        }
    }

    /// At the geographic poles evaluation is finite and agrees with a point 1e-6 degrees away.
    @Test func polesAreFiniteAndContinuous() throws {
        for (lat, nearLat) in [(90.0, 90.0 - 1e-6), (-90.0, -90.0 + 1e-6)] {
            let a = try WorldMagneticModel.evaluate(latitude: lat, longitude: 30, altitudeKm: 0, decimalYear: 2026.5)
            let b = try WorldMagneticModel.evaluate(latitude: nearLat, longitude: 30, altitudeKm: 0, decimalYear: 2026.5)
            #expect(a.north.isFinite && a.east.isFinite && a.down.isFinite && a.declination.isFinite)
            #expect(abs(a.north - b.north) < 0.01)
            #expect(abs(a.east - b.east) < 0.01)
            #expect(abs(a.down - b.down) < 0.01)
        }
    }
}
