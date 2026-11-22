import Foundation

/// Calendar arithmetic in UTC without `Calendar`, `DateFormatter` or any time-zone lookup (days-from-civil algorithm).
/// Used by the SWPC and HMS mappings, whose feeds give UTC times as bare strings.
enum SWPCUTC {
    /// Days since 1970-01-01 of a proleptic Gregorian date.
    static func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    /// The civil date of a day count since 1970-01-01.
    static func civil(fromDays z0: Int) -> (year: Int, month: Int, day: Int) {
        let z = z0 + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        return (yoe + era * 400 + (m <= 2 ? 1 : 0), m, d)
    }

    static func date(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0, second: Int = 0) -> Date {
        let days = daysFromCivil(year: year, month: month, day: day)
        return Date(timeIntervalSince1970: TimeInterval(days * 86_400 + hour * 3600 + minute * 60 + second))
    }

    /// Parses `yyyy-MM-dd'T'HH:mm[:ss]` (or a space instead of `T`) with an optional trailing `Z`, as UTC.
    /// Any other offset or trailing text returns nil: a time zone is never guessed.
    static func parse(_ text: String) -> Date? {
        var s = Substring(text.trimmingCharacters(in: .whitespaces))
        if s.hasSuffix("Z") { s = s.dropLast() }
        let parts = s.split(omittingEmptySubsequences: true, whereSeparator: { $0 == "T" || $0 == " " })
        guard parts.count == 2 else { return nil }
        let d = parts[0].split(separator: "-", omittingEmptySubsequences: false).map { Int($0) }
        let t = parts[1].split(separator: ":", omittingEmptySubsequences: false).map { Int($0) }
        guard d.count == 3, (2...3).contains(t.count), let y = d[0], let mo = d[1], let da = d[2],
              let h = t[0], let mi = t[1] else { return nil }
        let se = t.count == 3 ? t[2] : 0
        guard let sec = se, (1...12).contains(mo), (1...31).contains(da), (0...23).contains(h), (0...59).contains(mi),
              (0...60).contains(sec) else { return nil }
        return date(year: y, month: mo, day: da, hour: h, minute: mi, second: sec)
    }

    /// `yyyy-MM-dd'T'HH:mm:ss'Z'` for a date.
    static func iso(_ date: Date) -> String {
        let total = Int(date.timeIntervalSince1970.rounded(.down))
        let days = Int((Double(total) / 86_400).rounded(.down))
        let rem = total - days * 86_400
        let c = civil(fromDays: days)
        return String(format: "%04d-%02d-%02dT%02d:%02d:%02dZ", c.year, c.month, c.day, rem / 3600, (rem % 3600) / 60, rem % 60)
    }
}
