// Typed errors for the GRIB2 reader. Structural errors (the message cannot be walked) are thrown by `GRIB2File.init`;
// errors that only affect one field (unsupported template, count mismatch) are collected in `GRIB2File.failures`.

public enum GRIB2Error: Error, Sendable, Equatable {
    case badMagic(offset: Int)
    case unsupportedEdition(Int)
    case truncated(section: Int, offset: Int)
    case missingEndMarker(offset: Int)
    case sectionLengthOutOfRange(section: Int, length: Int)
    case unexpectedSection(Int)
    case invalidReferenceTime
    case missingSection(Int)
    case unsupportedGridTemplate(Int)
    case unsupportedScanningMode(Int)
    case invalidGrid(String)
    case unsupportedProductTemplate(Int)
    case unsupportedPacking(template: Int)
    case invalidPacking(String)
    case unsupportedBitmap(indicator: Int)
    case missingBitmap
    case valueCountMismatch(expected: Int, found: Int)
}

/// One field (section 7) that could not be decoded; the other fields of the file are unaffected.
public struct GRIB2FieldFailure: Sendable, Equatable {
    public let messageIndex: Int
    public let fieldIndex: Int
    public let error: GRIB2Error

    public init(messageIndex: Int, fieldIndex: Int, error: GRIB2Error) {
        (self.messageIndex, self.fieldIndex, self.error) = (messageIndex, fieldIndex, error)
    }
}
