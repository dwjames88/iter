import Foundation

// Sections 5, 6 and 7: simple packing (template 5.0), the bitmap, and the bit reader that unpacks the data.

/// Template 5.0: value = (R + X * 2^E) / 10^D, X an nbits-wide unsigned integer.
public struct GRIB2SimplePacking: Sendable, Equatable {
    /// Number of data points that carry a value (the bitmap's set bits, or all grid points without a bitmap).
    public let dataPointCount: Int
    public let reference: Float
    public let binaryScale: Int
    public let decimalScale: Int
    public let bitsPerValue: Int
    public let originalFieldType: Int

    init(section s: GRIB2Section) throws(GRIB2Error) {
        let template = try s.int(10, 2)
        guard template == 0 else { throw .unsupportedPacking(template: template) }
        dataPointCount = try s.int(6, 4)
        reference = try s.float32(12)
        binaryScale = try s.signed(16, 2)
        decimalScale = try s.signed(18, 2)
        bitsPerValue = try s.int(20, 1)
        originalFieldType = try s.int(21, 1)
        guard bitsPerValue <= 32 else { throw .invalidPacking("bits per value \(bitsPerValue)") }
        guard abs(binaryScale) <= 1000, abs(decimalScale) <= 300 else { throw .invalidPacking("scale factor out of range") }
    }

    /// Hard cap on grid size, so a corrupt Nx*Ny cannot ask for gigabytes.
    static let maxPoints = 1 << 26

    /// Values for all `gridPointCount` points in storage order; points the bitmap marks absent are NaN.
    func unpack(_ section7: GRIB2Section, gridPointCount: Int, bitmap: GRIB2Bitmap?) throws(GRIB2Error) -> [Double] {
        guard gridPointCount <= Self.maxPoints else { throw .invalidGrid("too many points") }
        var present = gridPointCount
        if let bitmap {
            guard bitmap.bytes.count >= (gridPointCount + 7) / 8 else { throw .truncated(section: 6, offset: bitmap.bytes.count) }
            present = bitmap.setCount(upTo: gridPointCount)
        }
        guard present == dataPointCount else { throw .valueCountMismatch(expected: dataPointCount, found: present) }

        let scale = pow(2.0, Double(binaryScale)), divisor = pow(10.0, Double(decimalScale)), r = Double(reference)
        var reader = GRIB2BitReader(section: section7, firstOctet: 6)
        var out = [Double](repeating: .nan, count: gridPointCount)
        let (totalBits, overflow) = present.multipliedReportingOverflow(by: bitsPerValue)
        guard !overflow, (totalBits + 7) / 8 <= reader.remainingBytes else {
            throw .truncated(section: 7, offset: section7.end)
        }
        for k in 0..<gridPointCount where bitmap?.isSet(k) ?? true {
            let x = bitsPerValue == 0 ? 0 : try reader.read(bitsPerValue)
            out[k] = (r + Double(x) * scale) / divisor
        }
        return out
    }
}

/// Section 6: which grid points carry data. Bit i (MSB first) set means point i has a value.
struct GRIB2Bitmap: Sendable, Equatable {
    let bytes: [UInt8]

    /// Indicator 0 reads the bitmap, 254 reuses `previous`, 255 means none (returns nil), others are predefined maps.
    init?(section s: GRIB2Section, previous: GRIB2Bitmap?) throws(GRIB2Error) {
        let indicator = try s.int(6, 1)
        switch indicator {
        case 0: bytes = Array(s.bytes[(s.start + 6)..<s.end])
        case 254:
            guard let previous else { throw .missingBitmap }
            bytes = previous.bytes
        case 255: return nil
        default: throw .unsupportedBitmap(indicator: indicator)
        }
    }

    func isSet(_ i: Int) -> Bool { i >= 0 && i >> 3 < bytes.count && bytes[i >> 3] & (0x80 >> UInt8(i & 7)) != 0 }

    func setCount(upTo n: Int) -> Int {
        var c = 0
        for i in 0..<n where isSet(i) { c += 1 }
        return c
    }
}

/// Reads nbits-wide big-endian unsigned integers from a section's payload; throws instead of reading past the end.
struct GRIB2BitReader {
    private let bytes: [UInt8]
    private let section: Int
    private var bitPos = 0
    private let endBit: Int

    init(section s: GRIB2Section, firstOctet: Int) {
        bytes = s.bytes
        section = s.number
        bitPos = max(0, s.start + firstOctet - 1) * 8
        endBit = s.end * 8
    }

    var remainingBytes: Int { max(0, (endBit - bitPos) / 8) }

    mutating func read(_ nbits: Int) throws(GRIB2Error) -> UInt64 {
        guard nbits >= 1, nbits <= 32, bitPos + nbits <= endBit else { throw .truncated(section: section, offset: bitPos / 8) }
        var value: UInt64 = 0
        var left = nbits
        while left > 0 {
            let bitInByte = bitPos & 7
            let take = min(left, 8 - bitInByte)
            let byte = UInt64(bytes[bitPos >> 3])
            value = value << UInt64(take) | ((byte >> UInt64(8 - bitInByte - take)) & ((1 << UInt64(take)) - 1))
            bitPos += take
            left -= take
        }
        return value
    }
}
