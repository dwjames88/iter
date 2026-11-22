import Foundation
import Testing
import IterModel
import IterSources
@testable import IterSourcesLive

@Suite("WMMProvider")
struct WMMProviderTests {
    static let whitney = Coordinate(latitude: 36.5785, longitude: -118.2923)
    static let swiss = Coordinate(latitude: 46.5586, longitude: 8.5610)
    static let date = w4ISODate("2026-11-22T12:00:00Z")
    let provider = WorldMagneticModelProvider(clock: ManualSourceClock(now: w4ISODate("2026-11-22T15:00:00Z")))

    @Test func declinationAtWhitneyAndTheSwissAlps() throws {
        // SOURCES.md: 11.817 degrees at W (NOAA's live API 11.81729), 3.623 at S, at sea level.
        let w = try provider.field(at: Self.whitney, elevationM: 0, on: Self.date)
        let s = try provider.field(at: Self.swiss, elevationM: 0, on: Self.date)
        #expect(abs(w.value.declinationDegrees - 11.817) < 0.03, "W \(w.value.declinationDegrees)")
        #expect(abs(s.value.declinationDegrees - 3.623) < 0.03, "S \(s.value.declinationDegrees)")
        // The summit height moves it by about a hundredth of a degree.
        let summit = try provider.field(at: Self.whitney, elevationM: 4416, on: Self.date)
        #expect(abs(summit.value.declinationDegrees - w.value.declinationDegrees) < 0.02)
        #expect(w.value.inclinationDegrees > 55 && w.value.inclinationDegrees < 65)
        #expect(w.value.totalIntensityNT > 45_000 && w.value.totalIntensityNT < 55_000)
        #expect(w.value.date == Self.date)
        #expect(!w.value.nearMagneticPole && !s.value.nearMagneticPole)
        #expect(w.provenance.source == .worldMagneticModel)
        #expect(w.provenance.origin?.computedOnDevice == true)
        #expect(w.provenance.origin?.tier == .military)
        #expect(w.provenance.model == "WMM-2025 (epoch 2025.0)")
        // True 90 degrees is magnetic 78.2 at W (east declination).
        #expect(abs(w.value.magneticBearing(fromTrue: 90) - (90 - w.value.declinationDegrees)) < 1e-9)
    }

    @Test func matchesTheFormatLayerExactly() throws {
        let direct = try WorldMagneticModel.evaluate(latitude: 36.5785, longitude: -118.2923, altitudeKm: 0, date: Self.date)
        let via = try provider.field(at: Self.whitney, elevationM: 0, on: Self.date)
        #expect(via.value.declinationDegrees == direct.declination)
        #expect(via.value.inclinationDegrees == direct.inclination)
        #expect(via.value.totalIntensityNT == direct.total)
    }

    @Test func nearTheMagneticPole() throws {
        let pole = Coordinate(latitude: 86, longitude: 139)
        let f = try provider.field(at: pole, elevationM: 0, on: Self.date)
        let h = try WorldMagneticModel.evaluate(latitude: 86, longitude: 139, altitudeKm: 0, date: Self.date).horizontal
        #expect(h < 6000, "H \(h)")
        #expect(f.value.nearMagneticPole)
    }

    @Test func outsideTheModelsValidityIsRefused() {
        #expect(throws: SourceError.outsideCoverage) { try provider.field(at: Self.whitney, elevationM: 0, on: w4ISODate("2031-01-01T00:00:00Z")) }
        #expect(throws: SourceError.outsideCoverage) { try provider.field(at: Self.whitney, elevationM: 0, on: w4ISODate("2024-12-31T23:00:00Z")) }
        #expect(throws: SourceError.invalidRequest("latitude must be within -90...90 and all inputs finite")) {
            try provider.field(at: Coordinate(latitude: 95, longitude: 0), elevationM: 0, on: Self.date)
        }
    }

    @Test func theModelsFirstAndLastDays() throws {
        _ = try provider.field(at: Self.whitney, elevationM: 0, on: w4ISODate("2025-01-01T00:00:00Z"))
        _ = try provider.field(at: Self.whitney, elevationM: 0, on: w4ISODate("2029-12-31T23:59:59Z"))
    }
}

@Suite("MGRSProvider")
struct MGRSProviderTests {
    static let whitney = Coordinate(latitude: 36.5785, longitude: -118.2923)
    static let swiss = Coordinate(latitude: 46.5586, longitude: 8.5610)
    let provider = MGRSProvider()

    /// Values from Fixtures/Geomag/mgrs-reference.json (NGA GEOTRANS via pyproj).
    @Test func forwardAgainstTheReferenceFile() throws {
        #expect(try provider.mgrs(for: Self.whitney, precision: 5).value == "11SLA8438148892")
        #expect(try provider.mgrs(for: Self.swiss, precision: 5).value == "32TMS6635056208")
        #expect(try provider.mgrs(for: Coordinate(latitude: 38.8977, longitude: -77.0365), precision: 5).value == "18SUJ2339407395")
        // Lower precision truncates (the cell contains the point), it does not round.
        #expect(try provider.mgrs(for: Self.whitney, precision: 3).value == "11SLA843488")
        #expect(try provider.mgrs(for: Self.whitney, precision: 1).value == "11SLA84")
        let r = try provider.mgrs(for: Self.whitney, precision: 5)
        #expect(r.provenance.source == .mgrs)
        #expect(r.provenance.origin?.computedOnDevice == true)
    }

    @Test func inverseGivesTheCellCentre() throws {
        // The reference file's "swLatLon" (python-mgrs toLatLon) is numerically the centre of the 1 m cell, which is what the
        // provider returns (the Formats layer's own corner is 0.7 m south-west of it).
        let w = try provider.coordinate(fromMGRS: "11SLA8438148892")
        #expect(w.distance(to: Coordinate(latitude: 36.57849767025916, longitude: -118.29230326252693)) < 0.05)
        let s = try provider.coordinate(fromMGRS: "32TMS6635056208")
        #expect(s.distance(to: Coordinate(latitude: 46.55860062370696, longitude: 8.560994442346328)) < 0.05)
        // The centre re-encodes to the same reference, and spaces and lower case are accepted.
        #expect(try provider.mgrs(for: w, precision: 5).value == "11SLA8438148892")
        #expect(try provider.mgrs(for: s, precision: 5).value == "32TMS6635056208")
        #expect(try provider.coordinate(fromMGRS: "32t ms 66350 56208") == s)
        // A 100 m reference decodes to the middle of its cell.
        let coarse = try provider.coordinate(fromMGRS: "11SLA843488")
        #expect(try provider.mgrs(for: coarse, precision: 3).value == "11SLA843488")
        #expect(coarse.distance(to: Self.whitney) < 100)
    }

    @Test func badInputIsAnInvalidRequest() {
        #expect(throws: SourceError.self) { try provider.mgrs(for: Self.whitney, precision: 0) }
        #expect(throws: SourceError.self) { try provider.mgrs(for: Self.whitney, precision: 6) }
        #expect(throws: SourceError.self) { try provider.mgrs(for: Coordinate(latitude: 91, longitude: 0), precision: 5) }
        for text in ["", "99ZZZ1234512345", "11SLA843", "hello"] {
            do {
                _ = try provider.coordinate(fromMGRS: text)
                Issue.record("expected a throw for \(text)")
            } catch let e as SourceError {
                guard case .invalidRequest = e else { Issue.record("wrong error \(e) for \(text)"); continue }
            } catch { Issue.record("wrong error type for \(text)") }
        }
    }
}
