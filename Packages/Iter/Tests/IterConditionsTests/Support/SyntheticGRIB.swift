// Copied from IterSourcesLiveTests (NOMADSSyntheticSupport, GRIB2TestSupport) so the budget test can serve NOMADS filter URLs.
import Foundation
import IterModel
import IterSources
import IterSourcesLive

/// A NOMADS that answers any filter URL with a synthetic GRIB2 file built for the requested box, cycle and forecast hour.
///
/// The file holds a regular lat/lon grid (5 x 5 points) spanning exactly the requested box, longitudes written 0...360 as
/// NOMADS does, with 2 m temperature `273.15 + forecastHour` K (so a row's `tempC` equals its forecast hour) and, for HRRR
/// files, 8 m smoke density 2e-8 kg/m3 (20 ug/m3). HRRR requests are answered with a lat/lon grid, not the real Lambert
/// grid: the decoder samples every grid type the same way, and a point outside the box reads nothing, so a file from the
/// wrong tile is noticed.
enum SyntheticNOMADS {
    struct Request: Sendable {
        let ref: NOMADSFileRef
        let box: NOMADSBox
    }

    private static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    /// The file, box and model a filter URL asks for.
    static func parse(_ url: URL) -> Request? {
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return nil }
        func v(_ n: String) -> String? { items.first { $0.name == n }?.value }
        guard let dir = v("dir"), let file = v("file"), let top = v("toplat").flatMap(Double.init),
              let bottom = v("bottomlat").flatMap(Double.init), let left = v("leftlon").flatMap(Double.init),
              let right = v("rightlon").flatMap(Double.init) else { return nil }
        let model: NOMADSModel = file.hasPrefix("hrrr") ? .hrrr : .gfs
        guard let dateText = dir.split(separator: "/").first?.split(separator: ".").last, dateText.count == 8,
              let y = Int(dateText.prefix(4)), let m = Int(dateText.dropFirst(4).prefix(2)), let d = Int(dateText.suffix(2)),
              let tRange = file.range(of: ".t"), let hh = Int(file[tRange.upperBound...].prefix(2)) else { return nil }
        let fh: Int?
        if model == .hrrr, let r = file.range(of: "wrfsfcf") { fh = Int(file[r.upperBound...].prefix(2)) }
        else { fh = file.split(separator: "f").last.flatMap { Int($0) } }
        guard let fh, let cycle = calendar.date(from: DateComponents(year: y, month: m, day: d, hour: hh)) else { return nil }
        return Request(ref: NOMADSFileRef(model: model, cycle: cycle, forecastHour: fh),
                       box: NOMADSBox(south: bottom, north: top, west: left, east: right))
    }

    private static func micro(_ degrees: Double) -> Int { Int((degrees * 1_000_000).rounded()) }

    static func file(for r: Request) -> Data {
        typealias B = GRIB2Builder
        let n = 5
        func lon360(_ x: Double) -> Double { x < 0 ? x + 360 : x }
        let west = lon360(r.box.west), east = lon360(r.box.east)
        let grid = B.latLonGrid(nx: n, ny: n, la1: micro(r.box.north), lo1: micro(west), la2: micro(r.box.south), lo2: micro(east),
                                di: micro((east - west) / Double(n - 1)), dj: micro((r.box.north - r.box.south) / Double(n - 1)))
        let c = calendar.dateComponents([.year, .month, .day, .hour], from: r.ref.cycle)
        var sections: [[UInt8]] = [
            B.identification(year: c.year!, month: c.month!, day: c.day!, hour: c.hour!), grid,
            B.product(category: 0, number: 0, forecastHours: r.ref.forecastHour, surfaceType: 103, scale: 0, scaled: 2),
            B.packing(count: n * n, reference: Float(273.15 + Double(r.ref.forecastHour)), bits: 0), B.noBitmap, B.data([]),
        ]
        if r.ref.model == .hrrr {
            sections += [
                B.product(category: 20, number: 0, forecastHours: r.ref.forecastHour, surfaceType: 103, scale: 0, scaled: 8),
                B.packing(count: n * n, reference: 2e-8, bits: 0), B.noBitmap, B.data([]),
            ]
        }
        return Data(B.message(discipline: 0, sections))
    }

    static let notPresent = Data("<html><body>Data file is not present</body></html>".utf8)
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
