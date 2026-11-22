import Foundation
import IterModel

// Typed views of the raw-string record columns, for the repositories and their callers. The conversions to and from
// the model values live in `Mapping/`; these are the small accessors the old records had.

extension PlaceRecord {
    public var origin: PlaceOrigin {
        get { PlaceOrigin(rawValue: originRaw) ?? .user }
        set { originRaw = newValue.rawValue }
    }

    public var category: PlaceCategory {
        get { PlaceCategory(rawValue: categoryRaw) ?? .landscape }
        set { categoryRaw = newValue.rawValue }
    }

    public var bestLight: [BestLight] {
        get { bestLightRaw.split(separator: ",").compactMap { BestLight(rawValue: String($0)) } }
        set { bestLightRaw = newValue.map(\.rawValue).joined(separator: ",") }
    }

    public var tags: [String] {
        get { tagsRaw.split(separator: ",").map(String.init) }
        set { tagsRaw = newValue.joined(separator: ",") }
    }

    public var coordinate: Coordinate {
        get { Coordinate(latitude: latitude, longitude: longitude) }
        set { latitude = newValue.latitude; longitude = newValue.longitude }
    }
}

extension StopRecord {
    public var session: LightWindowKind {
        get { LightWindowKind(rawValue: sessionRaw) ?? .goldenEvening }
        set { sessionRaw = newValue.rawValue }
    }

    public var kind: StopKind {
        get { StopKind(rawValue: kindRaw) ?? .light }
        set { kindRaw = newValue.rawValue }
    }

    public var fixedArrival: LocalTime? {
        get { LocalTime(iso: fixedArrivalISO) }
        set { fixedArrivalISO = newValue?.iso ?? "" }
    }
}

extension TripRecord {
    /// The stops of one day, in order.
    public func orderedStops(onDay day: Int) -> [StopRecord] { orderedStops.filter { $0.dayIndex == day } }

    /// The timing of the transfer into `day`: morning when absent, and always morning for the first day.
    public func transferTiming(intoDay day: Int) -> TransferTiming {
        day > 0 ? (transferTimings[day] ?? .morning) : .morning
    }
}

extension FolderRecord {
    public var kind: FolderKind {
        get { FolderKind(rawValue: kindRaw) ?? .trips }
        set { kindRaw = newValue.rawValue }
    }
}
