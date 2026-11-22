import Foundation
import IterSourcesLive

// Shared helpers for the GRIB2 tests: fixture loading, the ecCodes reference model, and a tiny message builder.

enum GRIB2Fixtures {
    static let hrrr = ["hrrr-W-20261122t12z-f01", "hrrr-W-20261122t12z-f06", "hrrr-W-20261122t12z-f12"]
    static let gfs = ["S", "W"].flatMap { p in ["f003", "f006", "f012"].map { "gfs-\(p)-20261122t06z-\($0)" } }
    static var all: [String] { hrrr + gfs }

    static func url(_ name: String, ext: String) -> URL? {
        Bundle.module.resourceURL?.appendingPathComponent("Fixtures/GRIB2/\(name).\(ext)")
    }

    static func data(_ name: String) throws -> Data {
        guard let u = url(name, ext: "grib2") else { throw CocoaError(.fileNoSuchFile) }
        return try Data(contentsOf: u)
    }

    static func reference(_ name: String) throws -> GRIB2Reference {
        guard let u = url(name, ext: "eccodes.json") else { throw CocoaError(.fileNoSuchFile) }
        return try JSONDecoder().decode(GRIB2Reference.self, from: Data(contentsOf: u))
    }
}

/// The JSON written by make-reference.py from ecCodes.
struct GRIB2Reference: Decodable {
    struct Point: Decodable { let lat: Double; let lon: Double }
    struct Grid: Decodable { let lats: [Double]; let lons: [Double] }
    struct Nearest: Decodable { let index: Int; let lat: Double; let lon: Double; let value: Double; let distance: Double }
    struct Message: Decodable {
        let discipline, parameterCategory, parameterNumber, typeOfFirstFixedSurface, level: Int
        let productDefinitionTemplateNumber, dataRepresentationTemplateNumber, gridDefinitionTemplateNumber: Int
        let forecastTime, dataDate, dataTime, nx, ny: Int
        let stepRange: String
        let values: [Double?]
        let nearest: Nearest
        let bilinear: Double?
    }
    let file: String
    let testPoint: Point
    let grid: Grid
    let messages: [Message]
}

/// Builds GRIB2 messages byte by byte, so tests can exercise corners the NOMADS fixtures never reach.
enum GRIB2Builder {
    static func be(_ v: Int, _ n: Int) -> [UInt8] { (0..<n).map { UInt8((v >> (8 * (n - 1 - $0))) & 0xFF) } }
    /// Sign-and-magnitude, as GRIB2 stores signed integers.
    static func sm(_ v: Int, _ n: Int) -> [UInt8] {
        var b = be(abs(v), n)
        if v < 0 { b[0] |= 0x80 }
        return b
    }

    static func section(_ number: Int, _ body: [UInt8]) -> [UInt8] { be(body.count + 5, 4) + [UInt8(number)] + body }

    static func message(discipline: Int = 0, _ sections: [[UInt8]]) -> [UInt8] {
        let body = sections.flatMap { $0 }
        return Array("GRIB".utf8) + [0, 0, UInt8(discipline), 2] + be(16 + body.count + 4, 8) + body + Array("7777".utf8)
    }

    static func identification(year: Int = 2026, month: Int = 11, day: Int = 22, hour: Int = 6) -> [UInt8] {
        section(1, be(7, 2) + be(0, 2) + [35, 0, 1] + be(year, 2) + [UInt8(month), UInt8(day), UInt8(hour), 0, 0, 0, 1])
    }

    /// Template 3.0, no earth radius given (shape 6), Di/Dj in micro-degrees.
    static func latLonGrid(nx: Int, ny: Int, la1: Int, lo1: Int, la2: Int, lo2: Int, di: Int, dj: Int, scan: Int = 0) -> [UInt8] {
        let earth: [UInt8] = [6] + [0] + be(0, 4) + [0] + be(0, 4) + [0] + be(0, 4)
        let body: [UInt8] = [0] + be(nx * ny, 4) + [0, 0] + be(0, 2) + earth + be(nx, 4) + be(ny, 4) + be(0, 4) + be(0xFFFF_FFFF, 4)
            + sm(la1, 4) + sm(lo1, 4) + [0x30] + sm(la2, 4) + sm(lo2, 4) + be(di, 4) + be(dj, 4) + [UInt8(scan)]
        return section(3, body)
    }

    static func lambertGrid(nx: Int, ny: Int, la1: Int, lo1: Int, laD: Int, loV: Int, dx: Int, dy: Int, latin1: Int, latin2: Int) -> [UInt8] {
        let earth: [UInt8] = [6] + [0] + be(0, 4) + [0] + be(0, 4) + [0] + be(0, 4)
        let body: [UInt8] = [0] + be(nx * ny, 4) + [0, 0] + be(30, 2) + earth + be(nx, 4) + be(ny, 4)
            + sm(la1, 4) + sm(lo1, 4) + [0x08] + sm(laD, 4) + sm(loV, 4) + be(dx, 4) + be(dy, 4) + [0, 0]
            + sm(latin1, 4) + sm(latin2, 4) + sm(-90_000_000, 4) + sm(0, 4)
        return section(3, body)
    }

    /// Template 4.0, or 4.8 when `statistical` gives (end y/m/d/h, process, range length in hours).
    static func product(
        category: Int, number: Int, forecastHours: Int, surfaceType: Int = 1, scale: Int = 0, scaled: Int = 0,
        statistical: (year: Int, month: Int, day: Int, hour: Int, process: Int, rangeHours: Int)? = nil
    ) -> [UInt8] {
        var body: [UInt8] = be(0, 2) + be(statistical == nil ? 0 : 8, 2) + [UInt8(category), UInt8(number), 2, 0, 0]
            + be(0, 2) + [0] + [1] + be(forecastHours, 4) + [UInt8(surfaceType)] + sm(scale, 1) + be(scaled, 4)
            + [255, 0] + be(0xFFFF_FFFF, 4)
        if let s = statistical {
            body += be(s.year, 2) + [UInt8(s.month), UInt8(s.day), UInt8(s.hour), 0, 0, 1] + be(0, 4)
                + [UInt8(s.process), 2, 1] + be(s.rangeHours, 4) + [255] + be(0, 4)
        }
        return section(4, body)
    }

    static func packing(count: Int, reference: Float, binary: [UInt8] = [0, 0], decimal: [UInt8] = [0, 0], bits: Int, template: Int = 0) -> [UInt8] {
        section(5, be(count, 4) + be(template, 2) + be(Int(reference.bitPattern), 4) + binary + decimal + [UInt8(bits), 0])
    }

    static func bitmap(_ bits: [Bool]) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: (bits.count + 7) / 8)
        for (i, b) in bits.enumerated() where b { bytes[i / 8] |= 0x80 >> UInt8(i % 8) }
        return section(6, [0] + bytes)
    }
    static let noBitmap = section(6, [255])
    static let reuseBitmap = section(6, [254])
    static func data(_ bytes: [UInt8]) -> [UInt8] { section(7, bytes) }
}
