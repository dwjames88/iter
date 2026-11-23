import SwiftUI
import CoreTransferable
import UniformTypeIdentifiers
import IterAstro
import IterFeatures
import IterModel
import IterSky
import IterStore
import IterUI

// Pure and small pieces the Library screens share: what a dragged trip or place carries, the clock and score hooks, the next
// light of a trip, and the editor's coordinate and time zone helpers.

// MARK: - Drag items

/// What a dragged trip card carries. Public so the shell's sidebar folders can accept it.
public struct TripDragItem: Codable, Hashable, Sendable, Transferable {
    public var tripID: UUID
    public init(tripID: UUID) { self.tripID = tripID }
    public static var transferRepresentation: some TransferRepresentation { CodableRepresentation(contentType: .iterTripCard) }
}

/// What a dragged place row carries. Public so the shell's sidebar folders can accept it.
public struct PlaceDragItem: Codable, Hashable, Sendable, Transferable {
    public var placeID: UUID
    public init(placeID: UUID) { self.placeID = placeID }
    public static var transferRepresentation: some TransferRepresentation { CodableRepresentation(contentType: .iterPlaceRow) }
}

extension UTType {
    /// In-app drags. Not declared in Info.plist on purpose: they never leave the app.
    public static let iterTripCard = UTType(exportedAs: "com.dwjames.iter.trip-card")
    public static let iterPlaceRow = UTType(exportedAs: "com.dwjames.iter.place-row")
}

// MARK: - Environment

extension EnvironmentValues {
    /// The clock "next light" is read against. The shell leaves the default (now); snapshots fix it.
    @Entry public var libraryClock: @Sendable () -> Date = { Date() }
    /// The score for a place's window on a day, when Conditions has one (the hero's single score chip). nil: the chip is unscored.
    @Entry public var libraryLightScore: (@MainActor @Sendable (Place, LocalDay, LightWindowKind) -> Int?)? = nil
}

extension FocusedValues {
    /// The saved place selected in Saved Places, so Edit > Edit Location (⌘E) can open its editor.
    @Entry public var selectedSavedPlace: UUID? = nil
}

// MARK: - Export

/// One trip as an `.iter` file, built when the share is performed.
struct LibraryTripExport: Transferable {
    var fileName: String
    var build: @MainActor @Sendable () -> Data?

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .iterTrip) { item in
            let data = await MainActor.run { item.build() }
            guard let data else { throw TripExportItem.Unavailable() }
            return data
        }
        .suggestedFileName { $0.fileName }
    }
}

// MARK: - Next light

/// The first light session of a trip that has not finished.
struct NextLight: Equatable {
    var stopName: String
    var place: Place
    var day: LocalDay
    var kind: LightWindowKind
    var start: Date
    var end: Date
    var zone: TimeZone

    @MainActor
    static func find(in trip: Trip, now: Date, engine: LightEngine = LightEngine(ephemeris: Astronomy())) -> NextLight? {
        let ordered = trip.stops.enumerated().sorted { a, b in
            a.element.dayIndex != b.element.dayIndex ? a.element.dayIndex < b.element.dayIndex : a.offset < b.offset
        }.map(\.element)
        for stop in ordered where stop.kind == .light {
            let day = trip.day(stop.dayIndex)
            let light = engine.dayLight(for: stop.place, on: day, inputs: nil, unavailable: [], now: now)
            guard let window = light.window(stop.session), window.span.end >= now else { continue }
            return NextLight(stopName: stop.place.name, place: stop.place, day: day, kind: stop.session, start: window.span.start,
                             end: window.span.end, zone: stop.place.timeZone)
        }
        return nil
    }
}

// MARK: - Place editor helpers

enum CoordinateText {
    /// "36.5786, -118.2920", "36.5786 -118.2920" or "36.5786,-118.2920": nil unless both numbers are valid.
    static func parse(_ text: String) -> Coordinate? {
        let parts = text.split(whereSeparator: { $0 == "," || $0 == ";" || $0.isWhitespace }).map(String.init)
        guard parts.count == 2, let lat = Double(parts[0]), let lon = Double(parts[1]),
              (-90...90).contains(lat), (-180...180).contains(lon) else { return nil }
        return Coordinate(latitude: lat, longitude: lon)
    }

    static func format(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(4)).grouping(.never)) }

    /// The time zone for a moved pin: the nearest catalogue spot's within 150 km, else the zone it had.
    static func zone(near coordinate: Coordinate, keeping current: String) -> String {
        var best: (meters: Double, zone: String)?
        for spot in CuratedSpots.all {
            let d = spot.coordinate.distance(to: coordinate)
            if d < 150_000, d < (best?.meters ?? .infinity) { best = (d, spot.timeZoneIdentifier) }
        }
        return best?.zone ?? current
    }
}

enum LibraryText {
    /// "Fri, Oct 9, 2026".
    static func fullDay(_ day: LocalDay) -> String {
        let utc = TimeZone(identifier: "UTC") ?? .gmt
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        return day.noon(in: utc).formatted(Date.FormatStyle(calendar: calendar, timeZone: utc).weekday(.abbreviated).month(.abbreviated).day().year())
    }

    static func tripSubtitle(_ row: TripRow) -> String {
        "\(TimeText.day(row.startDay))\(row.dayCount > 1 ? " – \(TimeText.day(row.endDay))" : "") • \(InflectedCount.days(row.dayCount)) • \(InflectedCount.stops(row.stopCount))"
    }
}
