import Foundation
import Synchronization
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

/// An `HTTPClient` serving `SyntheticNOMADS`. Records every request; can hold answers back, answer "not present" for
/// chosen files, and call a hook after each request.
final class SyntheticNOMADSClient: HTTPClient {
    private struct State {
        var requests: [SourceRequest] = []
        var gate: [CheckedContinuation<Void, Never>] = []
        var open = true
    }
    private let state = Mutex(State())
    private let missing: @Sendable (SyntheticNOMADS.Request) -> Bool
    private let onRequest: @Sendable (Int) -> Void

    init(missing: @escaping @Sendable (SyntheticNOMADS.Request) -> Bool = { _ in false },
         onRequest: @escaping @Sendable (Int) -> Void = { _ in }) {
        self.missing = missing
        self.onRequest = onRequest
    }

    var requests: [SourceRequest] { state.withLock { $0.requests } }
    var parsed: [SyntheticNOMADS.Request] { requests.compactMap { SyntheticNOMADS.parse($0.url) } }

    /// Holds every answer until `release()`.
    func hold() { state.withLock { $0.open = false } }

    func release() {
        let waiting = state.withLock { s -> [CheckedContinuation<Void, Never>] in
            s.open = true
            defer { s.gate = [] }
            return s.gate
        }
        for w in waiting { w.resume() }
    }

    func send(_ request: SourceRequest) async throws -> SourceResponse {
        let count = state.withLock { s -> Int in s.requests.append(request); return s.requests.count }
        onRequest(count)
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            let resumeNow = state.withLock { s -> Bool in
                if s.open { return true }
                s.gate.append(c)
                return false
            }
            if resumeNow { c.resume() }
        }
        guard let r = SyntheticNOMADS.parse(request.url) else { throw SourceError.http(status: 400, excerpt: "bad request") }
        if missing(r) { throw SourceError.http(status: 404, excerpt: "Data file is not present") }
        return SourceResponse(status: 200, body: SyntheticNOMADS.file(for: r), url: request.url, receivedAt: Date(timeIntervalSince1970: 0))
    }
}
