import Foundation
import CoreTransferable
import UniformTypeIdentifiers
import IterCore

/// The `.iter` file: one trip as JSON.
public struct TripDocument: Codable, Hashable, Sendable {
    public static let currentFormatVersion = 1
    public static let typeIdentifier = "com.dwjames.iter.trip"
    public static let fileExtension = "iter"

    public enum DocumentError: Error, Hashable, Sendable {
        case unsupportedVersion(Int)
        case corrupt
    }

    public var formatVersion: Int
    public var exportedAt: Date
    public var trip: TripPlan

    /// `exportedAt` is truncated to whole seconds so a document survives encode and decode unchanged.
    public init(trip: TripPlan, exportedAt: Date = .now, formatVersion: Int = TripDocument.currentFormatVersion) {
        self.formatVersion = formatVersion
        self.exportedAt = Date(timeIntervalSince1970: exportedAt.timeIntervalSince1970.rounded(.down))
        self.trip = trip
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> TripDocument {
        struct Header: Decodable { var formatVersion: Int }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let header = try? decoder.decode(Header.self, from: data) else { throw DocumentError.corrupt }
        guard header.formatVersion == currentFormatVersion else { throw DocumentError.unsupportedVersion(header.formatVersion) }
        guard let document = try? decoder.decode(TripDocument.self, from: data) else { throw DocumentError.corrupt }
        return document
    }

    /// A file name safe on every file system, with the `.iter` extension.
    public static func suggestedFileName(forTripNamed name: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.controlCharacters).union(.newlines)
        let cleaned = name.components(separatedBy: forbidden).joined(separator: " ")
            .split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        return (cleaned.isEmpty ? "Trip" : cleaned) + "." + fileExtension
    }
}

extension UTType {
    /// The `.iter` trip type. The app declares it as an exported type in its Info.plist.
    public static let iterTrip = UTType(exportedAs: TripDocument.typeIdentifier, conformingTo: .json)
}

extension TripDocument: Transferable {
    public static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(contentType: .iterTrip) { document in
            try document.encoded()
        } importing: { data in
            try TripDocument.decode(data)
        }
        .suggestedFileName { TripDocument.suggestedFileName(forTripNamed: $0.trip.name) }
    }
}
