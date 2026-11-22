import Foundation
import Testing
import IterSourcesLive

// Hand-built messages: corners the NOMADS fixtures do not reach.

private typealias B = GRIB2Builder

private func decode(_ bytes: [UInt8]) throws -> GRIB2File {
    do { return try GRIB2File(data: Data(bytes)) } catch { throw error }
}

@Suite struct GRIB2SyntheticTests {
    private let grid3x2 = B.latLonGrid(nx: 3, ny: 2, la1: 10_000_000, lo1: 20_000_000, la2: 9_000_000, lo2: 22_000_000, di: 1_000_000, dj: 1_000_000)

    @Test func bitmapAndConstantFieldsInOneMessage() throws {
        // Field 1: bitmap 101101 (4 present), nbits 0 -> constant 5.5. Field 2 reuses the bitmap (254), 8-bit data, E=1, D=1.
        let msg = B.message([
            B.identification(), grid3x2,
            B.product(category: 1, number: 8, forecastHours: 3), B.packing(count: 4, reference: 5.5, bits: 0),
            B.bitmap([true, false, true, true, false, true]), B.data([]),
            B.product(category: 0, number: 0, forecastHours: 3), B.packing(count: 4, reference: 10, binary: [0, 1], decimal: [0, 1], bits: 8),
            B.reuseBitmap, B.data([1, 2, 3, 4]),
        ])
        let file = try decode(msg)
        #expect(file.failures.isEmpty && file.fields.count == 2)
        let a = file.fields[0].values
        #expect(a.count == 6 && a[0] == 5.5 && a[1].isNaN && a[2] == 5.5 && a[3] == 5.5 && a[4].isNaN && a[5] == 5.5)
        let b = file.fields[1].values  // (10 + X * 2) / 10
        #expect(b[0] == 1.2 && b[1].isNaN && b[2] == 1.4 && b[3] == 1.6 && b[4].isNaN && b[5] == 1.8)
        // Points with no value are nil from the lookup APIs.
        #expect(file.fields[0].value(atLat: 10, lon: 21, interpolation: .nearest) == nil)
        #expect(file.fields[0].value(atLat: 10, lon: 20, interpolation: .nearest) == 5.5)
    }

    @Test func constantFieldWithoutBitmap() throws {
        let msg = B.message([B.identification(), grid3x2, B.product(category: 1, number: 7, forecastHours: 1),
            B.packing(count: 6, reference: 0, bits: 0), B.noBitmap, B.data([])])
        let f = try decode(msg).fields[0]
        #expect(f.values == [Double](repeating: 0, count: 6))
        #expect(f.value(atLat: 9.5, lon: 21.2) == 0)
    }

    @Test func signAndMagnitudeIntegers() throws {
        // E = 0x8004 is -4 and D = 0x8001 is -1: value = (1 + 16 * 2^-4) / 10^-1 = 20. Two's complement would give nonsense.
        let msg = B.message([B.identification(),
            B.latLonGrid(nx: 3, ny: 2, la1: -10_000_000, lo1: -20_000_000, la2: -11_000_000, lo2: -18_000_000, di: 1_000_000, dj: 1_000_000),
            B.product(category: 0, number: 0, forecastHours: 0, scale: -1, scaled: 25),
            B.packing(count: 6, reference: 1, binary: [0x80, 4], decimal: [0x80, 1], bits: 8), B.noBitmap, B.data([16, 0, 32, 48, 16, 16])])
        let f = try decode(msg).fields[0]
        #expect(f.packing.binaryScale == -4 && f.packing.decimalScale == -1)
        #expect(f.values == [20, 10, 30, 40, 20, 20])
        #expect(f.latitude(ofIndex: 0) == -10 && f.longitude(ofIndex: 0) == -20)  // sign bit on La1/Lo1
        #expect(f.product.firstSurface?.value == 250)  // scale factor -1 (0x81): 25 * 10^1
    }

    @Test func statisticalProductTemplate48() throws {
        let msg = B.message([B.identification(hour: 6), grid3x2,
            B.product(category: 1, number: 8, forecastHours: 0, statistical: (2026, 11, 22, 12, 1, 6)),
            B.packing(count: 6, reference: 0, bits: 0), B.noBitmap, B.data([]),
            B.product(category: 6, number: 3, forecastHours: 6, surfaceType: 214), B.packing(count: 6, reference: 0, bits: 0), B.noBitmap, B.data([])])
        let file = try decode(msg)
        let apcp = file.fields[0]
        let stat = try #require(apcp.product.statistical)
        #expect(apcp.product.templateNumber == 8 && stat.isAccumulation && stat.rangeHours == 6)
        let ref = Date(timeIntervalSince1970: 1_795_327_200)  // 2026-11-22 06:00:00 UTC
        #expect(apcp.identification.referenceTime == ref)
        #expect(apcp.validTime == ref.addingTimeInterval(6 * 3600) && apcp.forecastHour == 6)
        #expect(file.fields[1].product.statistical == nil && file.fields[1].forecastHour == 6)
        #expect(file.field(parameter: .totalPrecipitation, level: .surface, forecastHour: 6, statistical: true) != nil)
        #expect(file.field(parameter: .lowCloudCover, level: .lowCloudLayer, forecastHour: 6, statistical: false) != nil)
    }

    @Test func unsupportedPackingFailsOnlyThatField() throws {
        let msg = B.message([B.identification(), grid3x2,
            B.product(category: 0, number: 0, forecastHours: 0), B.packing(count: 6, reference: 0, bits: 8, template: 40), B.noBitmap, B.data([1, 2, 3, 4, 5, 6]),
            B.product(category: 0, number: 6, forecastHours: 0), B.packing(count: 6, reference: 0, bits: 8), B.noBitmap, B.data([1, 2, 3, 4, 5, 6])])
        let file = try decode(msg)
        #expect(file.failures == [GRIB2FieldFailure(messageIndex: 0, fieldIndex: 0, error: .unsupportedPacking(template: 40))])
        #expect(file.fields.count == 1 && file.fields[0].parameter == .dewPoint && file.fields[0].values == [1, 2, 3, 4, 5, 6])
    }

    @Test func unsupportedTemplatesAndMismatchesAreFieldErrors() throws {
        var p48 = B.product(category: 20, number: 102, forecastHours: 1)
        p48[7] = 0; p48[8] = 48  // template 4.48 is not parsed
        let wrongCount = B.message([B.identification(), grid3x2, B.product(category: 0, number: 0, forecastHours: 0),
            B.packing(count: 5, reference: 0, bits: 8), B.noBitmap, B.data([1, 2, 3, 4, 5, 6]),
            p48, B.packing(count: 6, reference: 0, bits: 0), B.noBitmap, B.data([]),
            B.product(category: 0, number: 0, forecastHours: 0), B.packing(count: 6, reference: 0, bits: 8), B.noBitmap, B.data([1, 2, 3])])
        let file = try decode(wrongCount)
        #expect(file.fields.isEmpty)
        let errors = file.failures.map(\.error)
        #expect(errors.count == 3 && errors[0] == .valueCountMismatch(expected: 5, found: 6) && errors[1] == .unsupportedProductTemplate(48))
        if case .truncated(let section, _)? = errors.last { #expect(section == 7) } else { Issue.record("expected truncated data") }
        var lambert = B.latLonGrid(nx: 3, ny: 2, la1: 0, lo1: 0, la2: 0, lo2: 0, di: 1, dj: 1)
        lambert[12] = 0; lambert[13] = 20  // grid template 3.20
        let polar = try decode(B.message([B.identification(), lambert, B.product(category: 0, number: 0, forecastHours: 0),
            B.packing(count: 6, reference: 0, bits: 0), B.noBitmap, B.data([])]))
        #expect(polar.failures.map(\.error) == [.unsupportedGridTemplate(20)])
    }

    @Test func scanningModes() throws {
        // Values 0...5 stored in each order; the same value must be found at the same place.
        let data: [UInt8] = [0, 1, 2, 3, 4, 5]
        func field(scan: Int, la1: Int, lo1: Int) throws -> GRIB2Field {
            try decode(B.message([B.identification(),
                B.latLonGrid(nx: 3, ny: 2, la1: la1, lo1: lo1, la2: 0, lo2: 0, di: 1_000_000, dj: 1_000_000, scan: scan),
                B.product(category: 0, number: 0, forecastHours: 0), B.packing(count: 6, reference: 0, bits: 8), B.noBitmap, B.data(data)])).fields[0]
        }
        let nw = try field(scan: 0x00, la1: 11_000_000, lo1: 20_000_000)  // N->S, W->E, rows
        #expect(nw.latitude(ofIndex: 3) == 10 && nw.longitude(ofIndex: 4) == 21)
        #expect(nw.value(atLat: 10, lon: 22, interpolation: .nearest) == 5)
        let sw = try field(scan: 0x40, la1: 10_000_000, lo1: 20_000_000)  // S->N
        #expect(sw.latitude(ofIndex: 3) == 11 && sw.value(atLat: 11, lon: 20, interpolation: .nearest) == 3)
        let ne = try field(scan: 0xC0, la1: 10_000_000, lo1: 22_000_000)  // E->W, S->N
        #expect(ne.longitude(ofIndex: 1) == 21 && ne.value(atLat: 10, lon: 20, interpolation: .nearest) == 2)
        let col = try field(scan: 0x20, la1: 11_000_000, lo1: 20_000_000)  // columns: index = i * ny + j
        #expect(col.latitude(ofIndex: 1) == 10 && col.longitude(ofIndex: 2) == 21 && col.value(atLat: 10, lon: 21, interpolation: .nearest) == 3)
        #expect(col.value(atLat: 10.5, lon: 20.5)! == (0 + 1 + 2 + 3) / 4.0)
        // Alternating row direction is not supported and says so.
        let alt = try decode(B.message([B.identification(),
            B.latLonGrid(nx: 3, ny: 2, la1: 0, lo1: 0, la2: 0, lo2: 0, di: 1, dj: 1, scan: 0x10),
            B.product(category: 0, number: 0, forecastHours: 0), B.packing(count: 6, reference: 0, bits: 0), B.noBitmap, B.data([])]))
        #expect(alt.failures.map(\.error) == [.unsupportedScanningMode(0x10)])
    }

    @Test func globalGridWrapsAroundTheAntimeridian() throws {
        // 4 columns 90 degrees apart starting at 0 (0, 90, 180, 270); one row pair.
        let f = try decode(B.message([B.identification(),
            B.latLonGrid(nx: 4, ny: 2, la1: 10_000_000, lo1: 0, la2: 9_000_000, lo2: 270_000_000, di: 90_000_000, dj: 1_000_000),
            B.product(category: 0, number: 0, forecastHours: 0), B.packing(count: 8, reference: 0, bits: 8), B.noBitmap,
            B.data([0, 10, 20, 30, 0, 10, 20, 30])])).fields[0]
        #expect(f.value(atLat: 10, lon: -45)! == 15)  // 315 degrees is halfway between column 270 (30) and the wrapped column 0 (0)
    }

    @Test func lambertTangentAndSecantRoundTrip() throws {
        for (l1, l2) in [(38_500_000, 38_500_000), (30_000_000, 60_000_000)] {
            let g = B.lambertGrid(nx: 5, ny: 4, la1: 36_000_000, lo1: -118_000_000 + 360_000_000, laD: l1, loV: 262_500_000, dx: 3_000_000, dy: 3_000_000, latin1: l1, latin2: l2)
            let f = try decode(B.message([B.identification(), g, B.product(category: 0, number: 0, forecastHours: 0),
                B.packing(count: 20, reference: 0, bits: 8), B.noBitmap, B.data(Array(0..<20))])).fields[0]
            #expect(abs((f.latitude(ofIndex: 0) ?? 0) - 36) < 1e-9 && abs((f.longitude(ofIndex: 0) ?? 0) + 118) < 1e-9, "latin \(l1)/\(l2)")
            for k in 0..<20 {
                let lat = try #require(f.latitude(ofIndex: k)), lon = try #require(f.longitude(ofIndex: k))
                #expect(f.nearestIndex(lat: lat, lon: lon) == k)
                #expect(f.value(atLat: lat, lon: lon) != nil && abs(f.value(atLat: lat, lon: lon)! - Double(k)) < 1e-6)
            }
            // Grid spacing on the ground is about 3 km (0.027 degrees of latitude per row at 3 km).
            let dLat = abs((f.latitude(ofIndex: 5) ?? 0) - (f.latitude(ofIndex: 0) ?? 0))
            #expect(dLat > 0.02 && dLat < 0.035)
        }
    }

    @Test func referenceTimeAndValidation() throws {
        let ok = try decode(B.message([B.identification(year: 2024, month: 2, day: 29, hour: 0), grid3x2,
            B.product(category: 0, number: 0, forecastHours: 0), B.packing(count: 6, reference: 0, bits: 0), B.noBitmap, B.data([])]))
        #expect(ok.fields[0].identification.referenceTime == Date(timeIntervalSince1970: 1_709_164_800))
        #expect(ok.fields[0].identification.referenceDateComponents.year == 2024)
        #expect(throws: GRIB2Error.invalidReferenceTime) {
            try decode(B.message([B.identification(year: 2026, month: 2, day: 29), grid3x2]))
        }
    }
}
