import Foundation
import IterModel
import IterSources
import IterSourcesLive

/// Shared helpers for the NOMADS tests.
enum NOMADSTest {
    /// 2026-11-22T00:00:00Z.
    static let day0 = Date(timeIntervalSince1970: 1_795_305_600)

    /// A UTC instant on 2026-11-22 plus whole `days`.
    static func at(_ hour: Int, _ minute: Int = 0, days: Int = 0) -> Date {
        day0.addingTimeInterval(TimeInterval(days * 86_400 + hour * 3600 + minute * 60))
    }

    static func query(_ request: SourceRequest, _ name: String) -> String? {
        URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value
    }

    static func file(_ request: SourceRequest) -> String { query(request, "file") ?? "" }
}

/// Rewrites a recorded GRIB2 file to look like another cycle and forecast hour, so provider tests can serve any hour
/// from the few real fixtures: section 1 reference time, section 4 forecast time and (template 4.8) end-of-interval time.
enum GRIBRetarget {
    private static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    static func make(_ data: Data, cycle: Date, forecastHour fh: Int) -> Data {
        var b = [UInt8](data)
        func be(_ at: Int, _ n: Int) -> Int { (0..<n).reduce(0) { $0 << 8 | Int(b[at + $1]) } }
        func put(_ at: Int, _ n: Int, _ v: Int) { for k in 0..<n { b[at + k] = UInt8((v >> (8 * (n - 1 - k))) & 0xFF) } }
        func putTime(_ at: Int, _ d: Date) {
            let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: d)
            put(at, 2, c.year!); put(at + 2, 1, c.month!); put(at + 3, 1, c.day!)
            put(at + 4, 1, c.hour!); put(at + 5, 1, c.minute!); put(at + 6, 1, c.second!)
        }
        let valid = cycle.addingTimeInterval(TimeInterval(fh) * 3600)
        var pos = 0
        while pos + 16 <= b.count, b[pos] == 0x47, b[pos + 1] == 0x52 {
            let total = be(pos + 8, 8)
            var cur = pos + 16
            while cur < pos + total - 4 {
                let len = be(cur, 4), number = b[cur + 4]
                if number == 1 { putTime(cur + 12, cycle) }
                if number == 4 {
                    let template = be(cur + 7, 2)
                    if template == 0 {
                        put(cur + 18, 4, fh)
                    } else if template == 8 {
                        let rangeHours = be(cur + 49, 4)
                        put(cur + 18, 4, max(0, fh - rangeHours))
                        putTime(cur + 34, valid)
                    }
                }
                cur += len
            }
            pos += total
        }
        return Data(b)
    }
}
