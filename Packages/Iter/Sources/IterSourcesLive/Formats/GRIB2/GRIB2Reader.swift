import Foundation

// GRIB2 (WMO FM 92 edition 2) reader: sections 0 to 8, multi-message files, several fields per message.
// Pure: bytes in, value types out. Every read is bounds-checked and failures are typed errors.

/// A decoded file: every field that could be decoded plus the ones that could not (with the reason).
public struct GRIB2File: Sendable {
    public let fields: [GRIB2Field]
    public let failures: [GRIB2FieldFailure]
    /// Byte offset of each message in the input, in order.
    public let messageOffsets: [Int]

    /// Parses every message in `data`; bytes between messages (padding, junk) are skipped by scanning for "GRIB".
    public init(data: Data) throws(GRIB2Error) {
        let bytes = [UInt8](data)
        var fields: [GRIB2Field] = [], failures: [GRIB2FieldFailure] = [], offsets: [Int] = []
        var pos = 0
        while pos < bytes.count {
            guard let start = Self.findMagic(bytes, from: pos) else {
                // A tail that is a proper prefix of "GRIB" is a cut-off message, not padding.
                let tail = bytes[pos...]
                if !offsets.isEmpty || !tail.isEmpty, tail.count < 4, tail.elementsEqual(Self.magic.prefix(tail.count)) {
                    throw .truncated(section: 0, offset: pos)
                }
                break
            }
            let message = try Self.parseMessage(bytes, at: start, index: offsets.count)
            offsets.append(start)
            fields += message.fields
            failures += message.failures
            pos = start + message.length
        }
        guard !offsets.isEmpty else { throw .badMagic(offset: 0) }
        self.fields = fields
        self.failures = failures
        self.messageOffsets = offsets
    }

    /// All fields with this parameter.
    public func fields(parameter: GRIB2Parameter) -> [GRIB2Field] {
        fields.filter { $0.parameter == parameter }
    }

    /// The first field in file order matching parameter, level and forecast hour (the valid time minus the reference
    /// time, in hours). `statistical`: `true` only accumulations/averages (product template 4.8), `false` only
    /// instantaneous fields, `nil` either.
    public func field(parameter: GRIB2Parameter, level: GRIB2Level, forecastHour: Double, statistical: Bool? = nil) -> GRIB2Field? {
        fields.first { f in
            f.parameter == parameter && level.matches(f.product.firstSurface)
                && f.forecastHour.map { abs($0 - forecastHour) < 1e-6 } == true
                && (statistical == nil || f.isStatistical == statistical)
        }
    }

    // MARK: Message walking

    private static let magic: [UInt8] = [0x47, 0x52, 0x49, 0x42]

    private static func findMagic(_ b: [UInt8], from: Int) -> Int? {
        guard b.count >= 4, from <= b.count - 4 else { return nil }
        for i in from...(b.count - 4) where b[i] == 0x47 && b[i + 1] == 0x52 && b[i + 2] == 0x49 && b[i + 3] == 0x42 { return i }
        return nil
    }

    private static func parseMessage(_ bytes: [UInt8], at start: Int, index: Int)
        throws(GRIB2Error) -> (length: Int, fields: [GRIB2Field], failures: [GRIB2FieldFailure])
    {
        guard start + 16 <= bytes.count else { throw .truncated(section: 0, offset: start) }
        let head = GRIB2Section(bytes: bytes, number: 0, start: start, end: bytes.count)
        let discipline = try head.int(7, 1)
        let edition = try head.int(8, 1)
        guard edition == 2 else { throw .unsupportedEdition(edition) }
        guard let length = Int(exactly: try head.uint(9, 8)), length >= 20 else {
            throw .sectionLengthOutOfRange(section: 0, length: Int(clamping: try head.uint(9, 8)))
        }
        let (endPos, overflow) = start.addingReportingOverflow(length)
        guard !overflow, endPos <= bytes.count else { throw .truncated(section: 0, offset: bytes.count) }
        guard bytes[(endPos - 4)..<endPos].elementsEqual("7777".utf8) else { throw .missingEndMarker(offset: endPos - 4) }

        var identification: GRIB2Identification?
        var grid: Result<GRIB2Grid, GRIB2Error>?
        var product: Result<GRIB2Product, GRIB2Error>?
        var packing: Result<GRIB2SimplePacking, GRIB2Error>?
        var bitmap: Result<GRIB2Bitmap?, GRIB2Error>?
        var lastBitmap: GRIB2Bitmap?
        var fields: [GRIB2Field] = [], failures: [GRIB2FieldFailure] = []

        var cursor = start + 16
        let limit = endPos - 4
        while cursor < limit {
            guard cursor + 5 <= limit else { throw .truncated(section: 0, offset: cursor) }
            let header = GRIB2Section(bytes: bytes, number: 0, start: cursor, end: limit)
            let sectionLength = try header.int(1, 4), number = try header.int(5, 1)
            guard sectionLength >= 5, sectionLength <= limit - cursor else {
                throw .sectionLengthOutOfRange(section: number, length: sectionLength)
            }
            let section = GRIB2Section(bytes: bytes, number: number, start: cursor, end: cursor + sectionLength)
            guard identification != nil || number == 1 else { throw .unexpectedSection(number) }
            switch number {
            case 1: identification = try GRIB2Identification(section: section)
            case 2: break
            case 3:
                grid = capture { () throws(GRIB2Error) in try GRIB2Grid(section: section) }
                product = nil; packing = nil; bitmap = nil; lastBitmap = nil
            case 4:
                product = capture { () throws(GRIB2Error) in try GRIB2Product(section: section, discipline: discipline) }
                packing = nil; bitmap = nil
            case 5: packing = capture { () throws(GRIB2Error) in try GRIB2SimplePacking(section: section) }
            case 6:
                bitmap = capture { () throws(GRIB2Error) in try GRIB2Bitmap(section: section, previous: lastBitmap) }
                if case .success(let b?) = bitmap { lastBitmap = b }
            case 7:
                let ordinal = failures.count + fields.count
                do throws(GRIB2Error) {
                    guard let identification else { throw GRIB2Error.missingSection(1) }
                    fields.append(try Self.buildField(
                        section7: section, identification: identification, grid: grid, product: product, packing: packing,
                        bitmap: bitmap, messageIndex: index, fieldIndex: ordinal))
                } catch {
                    failures.append(GRIB2FieldFailure(messageIndex: index, fieldIndex: ordinal, error: error))
                }
                // A following repetition must bring its own sections 5 and 6 (and 4).
                product = nil; packing = nil; bitmap = nil
            default: throw .unexpectedSection(number)
            }
            cursor += sectionLength
        }
        return (length, fields, failures)
    }

    private static func buildField(
        section7: GRIB2Section, identification: GRIB2Identification, grid: Result<GRIB2Grid, GRIB2Error>?,
        product: Result<GRIB2Product, GRIB2Error>?, packing: Result<GRIB2SimplePacking, GRIB2Error>?,
        bitmap: Result<GRIB2Bitmap?, GRIB2Error>?, messageIndex: Int, fieldIndex: Int
    ) throws(GRIB2Error) -> GRIB2Field {
        guard let grid else { throw .missingSection(3) }
        guard let product else { throw .missingSection(4) }
        guard let packing else { throw .missingSection(5) }
        guard let bitmap else { throw .missingSection(6) }
        let g = try grid.get(), p = try product.get(), k = try packing.get(), b = try bitmap.get()
        let values = try k.unpack(section7, gridPointCount: g.pointCount, bitmap: b)
        return GRIB2Field(
            identification: identification, grid: g, product: p, packing: k, values: values,
            messageIndex: messageIndex, fieldIndex: fieldIndex)
    }
}

func capture<T>(_ body: () throws(GRIB2Error) -> T) -> Result<T, GRIB2Error> {
    do throws(GRIB2Error) { return .success(try body()) } catch { return .failure(error) }
}

// MARK: Section bytes

/// The bytes of one section, addressed by the spec's 1-based octet numbers; every read is bounds-checked.
struct GRIB2Section {
    let bytes: [UInt8]
    let number: Int
    let start: Int
    let end: Int  // exclusive

    var length: Int { end - start }

    func uint(_ octet: Int, _ count: Int) throws(GRIB2Error) -> UInt64 {
        let pos = start &+ octet &- 1
        guard octet >= 1, count >= 1, count <= 8, pos &+ count <= end else {
            throw .truncated(section: number, offset: pos)
        }
        var v: UInt64 = 0
        for k in 0..<count { v = v << 8 | UInt64(bytes[pos + k]) }
        return v
    }

    /// Unsigned value of at most 4 octets.
    func int(_ octet: Int, _ count: Int) throws(GRIB2Error) -> Int { Int(try uint(octet, count)) }

    /// GRIB2 signed integers are sign-and-magnitude, not two's complement.
    func signed(_ octet: Int, _ count: Int) throws(GRIB2Error) -> Int {
        let raw = try uint(octet, count)
        let signBit: UInt64 = 1 << UInt64(8 * count - 1)
        let magnitude = Int(raw & (signBit - 1))
        return raw & signBit != 0 ? -magnitude : magnitude
    }

    func float32(_ octet: Int) throws(GRIB2Error) -> Float { Float(bitPattern: UInt32(try uint(octet, 4))) }
}

// MARK: Section 1

public struct GRIB2Identification: Sendable, Equatable {
    public let originatingCentre: Int
    public let originatingSubCentre: Int
    public let masterTablesVersion: Int
    public let localTablesVersion: Int
    /// Code table 1.2: 0 analysis, 1 start of forecast, 2 verifying time of forecast, 3 observation time.
    public let significanceOfReferenceTime: Int
    /// Reference time in UTC.
    public let referenceDateComponents: DateComponents
    public let referenceTime: Date
    public let productionStatus: Int
    public let typeOfData: Int

    init(section s: GRIB2Section) throws(GRIB2Error) {
        originatingCentre = try s.int(6, 2)
        originatingSubCentre = try s.int(8, 2)
        masterTablesVersion = try s.int(10, 1)
        localTablesVersion = try s.int(11, 1)
        significanceOfReferenceTime = try s.int(12, 1)
        let (y, mo, d, h, mi, sec) = (try s.int(13, 2), try s.int(15, 1), try s.int(16, 1), try s.int(17, 1), try s.int(18, 1), try s.int(19, 1))
        guard let seconds = GRIB2Time.epochSeconds(year: y, month: mo, day: d, hour: h, minute: mi, second: sec) else {
            throw .invalidReferenceTime
        }
        var c = DateComponents()
        c.calendar = GRIB2Time.calendar
        c.timeZone = TimeZone(identifier: "UTC")
        (c.year, c.month, c.day, c.hour, c.minute, c.second) = (y, mo, d, h, mi, sec)
        referenceDateComponents = c
        referenceTime = Date(timeIntervalSince1970: TimeInterval(seconds))
        productionStatus = try s.int(20, 1)
        typeOfData = try s.int(21, 1)
    }
}

/// Calendar arithmetic without a clock or `Calendar` lookups: proleptic Gregorian, UTC.
enum GRIB2Time {
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC") ?? c.timeZone
        return c
    }()

    static func epochSeconds(year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int) -> Int? {
        guard (1...12).contains(month), day >= 1, hour < 24, minute < 60, second < 60 else { return nil }
        let leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
        let monthDays = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        guard day <= monthDays[month - 1] else { return nil }
        // Days from civil (H. Hinnant).
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        let days = era * 146_097 + doe - 719_468
        return days * 86_400 + hour * 3600 + minute * 60 + second
    }
}

// MARK: Field

/// One decoded field: grid, product, packing and the values in storage (scan) order. Missing points are NaN.
public struct GRIB2Field: Sendable {
    public let identification: GRIB2Identification
    public let grid: GRIB2Grid
    public let product: GRIB2Product
    public let packing: GRIB2SimplePacking
    public let values: [Double]
    public let messageIndex: Int
    public let fieldIndex: Int

    public var parameter: GRIB2Parameter { product.parameter }
    public var isStatistical: Bool { product.statistical != nil }

    /// Valid time: the end of the interval for statistically processed fields, else reference time plus forecast time.
    public var validTime: Date? {
        if let s = product.statistical { return s.endOfInterval }
        guard let seconds = product.forecastSeconds else { return nil }
        return identification.referenceTime.addingTimeInterval(TimeInterval(seconds))
    }

    /// Hours from reference time to valid time.
    public var forecastHour: Double? { validTime.map { $0.timeIntervalSince(identification.referenceTime) / 3600 } }

    public func latitude(ofIndex i: Int) -> Double? { grid.coordinate(ofIndex: i)?.latitude }
    public func longitude(ofIndex i: Int) -> Double? { grid.coordinate(ofIndex: i)?.longitude }
    public func nearestIndex(lat: Double, lon: Double) -> Int? { grid.nearestIndex(lat: lat, lon: lon) }

    public enum Interpolation: Sendable { case nearest, bilinear }

    /// The value at a point, or nil outside the grid, or when a needed grid point is missing (NaN).
    public func value(atLat lat: Double, lon: Double, interpolation: Interpolation = .bilinear) -> Double? {
        let v: Double?
        switch interpolation {
        case .nearest: v = nearestIndex(lat: lat, lon: lon).map { values[$0] }
        case .bilinear: v = grid.bilinearStencil(lat: lat, lon: lon).map { s in
            s.weights.indices.reduce(0.0) { $0 + s.weights[$1] * values[s.indices[$1]] } }
        }
        guard let v, v.isFinite else { return nil }
        return v
    }
}
