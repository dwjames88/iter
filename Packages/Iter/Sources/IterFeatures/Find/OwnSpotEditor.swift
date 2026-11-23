import Foundation
import Observation
import IterModel
import IterSources
import IterStore

// Your own spots: drop a pin, drag it, Adjust Location, type or paste coordinates, and read a position in lat/lon, MGRS
// and magnetic declination. Every change to the library goes through `LibraryStore.places` (one named undo each); this
// model never sees a `ModelContext`.

/// The Latitude and Longitude text fields of a spot, with validation and Paste Coordinates (ported from `CoordinateFields`).
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

    public var latitudeProblem: String? { latitude == nil ? "Latitude is a number from -90 to 90." : nil }
    public var longitudeProblem: String? { longitude == nil ? "Longitude is a number from -180 to 180." : nil }

    /// Takes a coordinate from outside (a drag, the map): rewrites both fields.
    public mutating func set(_ coordinate: Coordinate) {
        latitudeText = Self.format(coordinate.latitude)
        longitudeText = Self.format(coordinate.longitude)
        pasteFailed = false
    }

    /// Paste Coordinates: "lat, lon", degrees with N/S/E/W, degrees-minutes-seconds, or an Apple Maps link. False (and
    /// nothing changes) when the text holds no coordinate.
    @discardableResult
    public mutating func paste(_ text: String) -> Bool {
        guard let c = CoordinateParser.parse(text) else { pasteFailed = true; return false }
        set(c)
        return true
    }
}

/// A position written three ways, each with where it came from. Computed on the device from published standards.
public struct PositionReadout: Equatable, Sendable {
    public var latitudeText: String
    public var longitudeText: String
    /// "12S WC 12345 67890" style grid reference (precision 5 = 1 m), nil when the grid does not cover the point (poles).
    public var mgrs: String?
    /// "Military Grid Reference System, Military-origin standard (NGA), computed on device".
    public var mgrsSource: String?
    /// "10.4° E" (east positive); nil when the model could not answer.
    public var declinationText: String?
    /// "World Magnetic Model 2025, Military-origin (NGA and UK Defence Geographic Centre) via NOAA NCEI".
    public var declinationSource: String?
    /// A plain line when the declination is unreliable (near a magnetic pole) or missing.
    public var declinationNote: String?
    public var inclinationText: String?

    /// "38.3884°N 109.8680°W".
    public var decimalText: String { "\(latitudeText), \(longitudeText)" }
}

/// The result of dropping a pin: the saved place and whether its time zone is a longitude estimate.
public struct DroppedSpot: Equatable, Sendable {
    public var place: Place
    public var timeZoneIsEstimate: Bool
    public var nameFromLookup: Bool
}

/// Adjust Location in progress: the map pans under a crosshair; Done saves the centre, Cancel leaves the spot where it was.
public struct AdjustSession: Equatable, Sendable {
    public var placeID: UUID
    public var original: Coordinate
    public var center: Coordinate
}

@MainActor @Observable
public final class OwnSpotEditor {
    @ObservationIgnored private let library: LibraryStore
    @ObservationIgnored private let geocoder: any Geocoder
    @ObservationIgnored private let magnetic: any MagneticModelProvider
    @ObservationIgnored private let grid: any GridReferenceProvider
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private var dropGeneration = 0

    /// Add Spot mode: the next click on the map drops a pin.
    public private(set) var isAdding = false
    /// The pin being dragged: its id and the coordinate under the pointer. The stored coordinate changes only on drop.
    public private(set) var dragging: (id: UUID, coordinate: Coordinate)?
    public private(set) var adjusting: AdjustSession?
    /// Fields for the spot being edited (Paste Coordinates writes here; `applyFields` moves the spot).
    public var fields = CoordinateFields(Coordinate(latitude: 0, longitude: 0))
    public private(set) var fieldsPlaceID: UUID?
    public private(set) var lastDropped: DroppedSpot?
    /// True while the reverse lookup for a dropped pin is running.
    public private(set) var isDropping = false

    public init(library: LibraryStore, geocoder: any Geocoder, magnetic: any MagneticModelProvider, grid: any GridReferenceProvider,
                now: @escaping @Sendable () -> Date) {
        self.library = library
        self.geocoder = geocoder
        self.magnetic = magnetic
        self.grid = grid
        self.now = now
    }

    // MARK: Adding

    public func beginAdding() { isAdding = true }
    public func cancelAdding() { isAdding = false; dropGeneration += 1; isDropping = false }

    /// Drops a pin: looks the name and locality up (`Geocoder.reverse`), estimates the time zone when the lookup gave none,
    /// and creates the spot (one undo, "Create Spot"). A failed lookup still creates it, named "Dropped Pin". Returns nil
    /// when a newer drop or a cancel superseded this one.
    @discardableResult
    public func drop(at coordinate: Coordinate) async -> DroppedSpot? {
        dropGeneration += 1
        let mine = dropGeneration
        isDropping = true
        let result = try? await geocoder.reverse(coordinate)
        guard mine == dropGeneration else { return nil }
        isDropping = false
        isAdding = false
        let name = Self.cleanName(result?.name) ?? "Dropped Pin"
        let zoneID = result?.timeZoneIdentifier.flatMap { TimeZone(identifier: $0) != nil ? $0 : nil }
        let record = library.places.createUserSpot(name: name, locality: result?.formattedAddress ?? "", coordinate: coordinate,
                                                   timeZoneIdentifier: zoneID ?? Self.estimatedTimeZone(at: coordinate))
        let spot = DroppedSpot(place: record.value(), timeZoneIsEstimate: zoneID == nil, nameFromLookup: Self.cleanName(result?.name) != nil)
        lastDropped = spot
        return spot
    }

    static func cleanName(_ name: String?) -> String? {
        guard let t = name?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }

    /// A fixed-offset zone from the longitude (`Etc/GMT+7` for -105). Wrong near zone borders and for daylight time, so the
    /// spot is marked as an estimate until a lookup supplies the real zone.
    public static func estimatedTimeZone(at coordinate: Coordinate) -> String {
        let hours = Int((coordinate.longitude / 15).rounded())
        if hours == 0 { return "Etc/GMT" }
        // POSIX sign: Etc/GMT+7 is seven hours BEHIND UTC (longitude west).
        return hours < 0 ? "Etc/GMT+\(-hours)" : "Etc/GMT-\(hours)"
    }

    // MARK: Moving

    /// Whether the place is one of your own (only those move).
    public func canMove(_ id: UUID) -> Bool { library.places.place(id: id)?.origin == .user }

    /// Moves one of your own spots to exactly `coordinate` (no lookup replaces it). One undo step, "Move Spot".
    @discardableResult
    public func move(_ id: UUID, to coordinate: Coordinate) -> Bool {
        guard canMove(id), let record = library.places.place(id: id) else { return false }
        library.places.moveSpot(record, to: coordinate)
        if fieldsPlaceID == id { fields.set(coordinate) }
        return true
    }

    /// Where to draw a pin: the drag's or Adjust Location's coordinate while one runs, else the stored one.
    public func displayCoordinate(for id: UUID, stored: Coordinate) -> Coordinate {
        if let dragging, dragging.id == id { return dragging.coordinate }
        if let adjusting, adjusting.placeID == id { return adjusting.center }
        return stored
    }

    @discardableResult
    public func beginDrag(_ id: UUID) -> Bool {
        guard canMove(id), adjusting == nil, !isAdding, let record = library.places.place(id: id) else { return false }
        dragging = (id, record.coordinate)
        return true
    }

    public func drag(to coordinate: Coordinate) {
        guard let current = dragging else { return }
        dragging = (current.id, coordinate)
    }

    /// The drop. `commit` stores the dragged-to coordinate (one "Move Spot"); otherwise the pin goes back.
    public func endDrag(commit: Bool) {
        guard let current = dragging else { return }
        dragging = nil
        if commit { move(current.id, to: current.coordinate) }
    }

    // MARK: Adjust Location

    /// Begins Adjust Location: remembers where the spot was; the view pans the map to it.
    @discardableResult
    public func beginAdjusting(_ id: UUID) -> Bool {
        guard canMove(id), dragging == nil, adjusting == nil, let record = library.places.place(id: id) else { return false }
        adjusting = AdjustSession(placeID: id, original: record.coordinate, center: record.coordinate)
        return true
    }

    public func adjustCenterChanged(_ center: Coordinate) { adjusting?.center = center }

    /// Done saves the crosshair's coordinate (one "Move Spot"); Cancel restores the original and writes nothing.
    public func finishAdjusting(commit: Bool) {
        guard let session = adjusting else { return }
        adjusting = nil
        if commit { move(session.placeID, to: session.center) } else if fieldsPlaceID == session.placeID { fields.set(session.original) }
    }

    // MARK: Coordinate fields

    /// Loads a spot's coordinate into the fields.
    public func editFields(for id: UUID) {
        guard let record = library.places.place(id: id) else { return }
        fieldsPlaceID = id
        fields = CoordinateFields(record.coordinate)
    }

    @discardableResult
    public func pasteCoordinates(_ text: String) -> Bool { fields.paste(text) }

    /// Moves the spot being edited to the (valid) fields. False when the fields do not hold a coordinate or the spot is not yours.
    @discardableResult
    public func applyFields() -> Bool {
        guard let id = fieldsPlaceID, let c = fields.coordinate else { return false }
        return move(id, to: c)
    }

    // MARK: Readout

    /// Latitude, longitude, MGRS and magnetic declination for a point, each with its provenance.
    public func readout(for coordinate: Coordinate, elevationMeters: Double? = nil) -> PositionReadout {
        var out = PositionReadout(latitudeText: Self.degrees(coordinate.latitude, positive: "N", negative: "S"),
                                  longitudeText: Self.degrees(coordinate.longitude, positive: "E", negative: "W"))
        if let g = try? grid.mgrs(for: coordinate, precision: 5) {
            out.mgrs = Self.spaced(g.value)
            out.mgrsSource = Self.sourceLine(grid.descriptor, g.provenance)
        }
        if let m = try? magnetic.field(at: coordinate, elevationM: elevationMeters ?? 0, on: now()) {
            let d = m.value.declinationDegrees
            out.declinationText = String(format: "%.1f° %@", abs(d), d >= 0 ? "E" : "W")
            out.inclinationText = String(format: "%.1f°", m.value.inclinationDegrees)
            out.declinationSource = Self.sourceLine(magnetic.descriptor, m.provenance)
            if m.value.nearMagneticPole { out.declinationNote = "Close to a magnetic pole: a compass is unreliable here." }
        } else {
            out.declinationNote = "Magnetic declination is not available for this point."
        }
        return out
    }

    static func degrees(_ value: Double, positive: String, negative: String) -> String {
        String(format: "%.4f°%@", abs(value), value >= 0 ? positive : negative)
    }

    /// "12SWC1234567890" to "12S WC 12345 67890".
    static func spaced(_ mgrs: String) -> String {
        guard !mgrs.contains(" ") else { return mgrs }
        let chars = Array(mgrs)
        guard let firstLetter = chars.firstIndex(where: \.isLetter), chars.count > firstLetter + 3 else { return mgrs }
        let zone = String(chars[0...firstLetter])
        let square = String(chars[(firstLetter + 1)...(firstLetter + 2)])
        let digits = Array(chars[(firstLetter + 3)...])
        let half = digits.count / 2
        return "\(zone) \(square) \(String(digits[0..<half])) \(String(digits[half...]))"
    }

    static func sourceLine(_ descriptor: SourceDescriptor, _ provenance: Provenance) -> String {
        let origin = (provenance.origin ?? descriptor.origin).label
        return "\(descriptor.name), \(origin)"
    }
}
