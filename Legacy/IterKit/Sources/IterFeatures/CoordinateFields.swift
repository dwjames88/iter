import Foundation
import IterCore

/// The Latitude and Longitude text fields of a place, with validation and Paste Coordinates. Platform-neutral so it is
/// tested; `CoordinateFieldsSection` (App/Sources/Components) is the form section that edits one.
public struct CoordinateFields: Equatable, Sendable {
    public var latitudeText: String
    public var longitudeText: String
    /// The last paste found no coordinate in the text.
    public private(set) var pasteFailed = false

    public init(_ coordinate: Coordinate) {
        latitudeText = Self.format(coordinate.latitude)
        longitudeText = Self.format(coordinate.longitude)
    }

    /// Decimal degrees, up to six places (about 10 cm), without trailing zeros: "38.5", "-109.549412".
    public static func format(_ degrees: Double) -> String {
        var text = String(format: "%.6f", degrees)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text == "-0" ? "0" : text
    }

    public var latitude: Double? { CoordinateParser.parseDegrees(latitudeText, axis: .latitude) }
    public var longitude: Double? { CoordinateParser.parseDegrees(longitudeText, axis: .longitude) }

    /// Nil until both fields hold a valid value.
    public var coordinate: Coordinate? {
        guard let latitude, let longitude else { return nil }
        return Coordinate(latitude: latitude, longitude: longitude)
    }

    public var latitudeProblem: String? {
        latitude == nil ? String(localized: "Latitude is a number from -90 to 90.", comment: "Validation: latitude field") : nil
    }

    public var longitudeProblem: String? {
        longitude == nil ? String(localized: "Longitude is a number from -180 to 180.", comment: "Validation: longitude field") : nil
    }

    /// Takes a coordinate from outside (a drag, the map): rewrites both fields.
    public mutating func set(_ coordinate: Coordinate) {
        latitudeText = Self.format(coordinate.latitude)
        longitudeText = Self.format(coordinate.longitude)
        pasteFailed = false
    }

    /// Paste Coordinates: "lat, lon", with degree signs and N/S/E/W, or an Apple Maps link. False (and nothing changes) otherwise.
    @discardableResult
    public mutating func paste(_ text: String) -> Bool {
        guard let c = CoordinateParser.parse(text) else { pasteFailed = true; return false }
        set(c)
        return true
    }
}

/// Where a map pin sits on its coordinate. Chips and the selected pin carry a pointer, and the tip of it is the coordinate for
/// both: a chip used to be centred on it while the selected pin hung from it by the tip, so selecting a pin made it jump
/// up the map by about its height. Dots are round and centred.
public enum MapPinAnchor {
    public static func vertical(for style: ExplorePinStyle) -> Double { style == .dot ? 0.5 : 1 }
    public static let horizontal = 0.5
}
