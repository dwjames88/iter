import Foundation
import IterCore

/// A ready-made route the user can start a trip from. The app localizes names by `id`; `defaultName` is English.
public struct TripTemplate: Identifiable, Sendable, Hashable {
    public struct Stop: Sendable, Hashable {
        public var spotID: String
        public var dayIndex: Int
        public var session: LightWindowKind

        public init(spotID: String, dayIndex: Int, session: LightWindowKind) {
            self.spotID = spotID
            self.dayIndex = dayIndex
            self.session = session
        }
    }

    /// Stable, e.g. "canyon-country".
    public var id: String
    public var defaultName: String
    public var dayCount: Int
    /// In order within each day.
    public var stops: [Stop]

    public init(id: String, defaultName: String, dayCount: Int, stops: [Stop]) {
        self.id = id
        self.defaultName = defaultName
        self.dayCount = dayCount
        self.stops = stops
    }
}

public enum TripTemplates {
    public static let all: [TripTemplate] = [canyonCountry, easternSierra, yosemite]

    public static func template(id: String) -> TripTemplate? { all.first { $0.id == id } }

    /// Horseshoe Bend, Monument Valley, Moab and the San Rafael Swell; long drives are on the mornings after a sunset stop.
    static let canyonCountry = TripTemplate(id: "canyon-country", defaultName: "Canyon Country", dayCount: 4, stops: [
        .init(spotID: "horseshoe-bend", dayIndex: 0, session: .goldenEvening),
        .init(spotID: "monument-valley", dayIndex: 1, session: .goldenMorning),
        .init(spotID: "dead-horse-point", dayIndex: 1, session: .goldenEvening),
        .init(spotID: "mesa-arch", dayIndex: 2, session: .goldenMorning),
        .init(spotID: "delicate-arch", dayIndex: 2, session: .goldenEvening),
        .init(spotID: "goblin-valley", dayIndex: 3, session: .goldenEvening),
    ])

    /// South to north along US-395, Little Lake to Mono Lake.
    static let easternSierra = TripTemplate(id: "eastern-sierra", defaultName: "Eastern Sierra", dayCount: 3, stops: [
        .init(spotID: "fossil-falls", dayIndex: 0, session: .goldenEvening),
        .init(spotID: "alabama-hills", dayIndex: 0, session: .night),
        .init(spotID: "alabama-hills", dayIndex: 1, session: .goldenMorning),
        .init(spotID: "lake-sabrina", dayIndex: 1, session: .goldenEvening),
        .init(spotID: "convict-lake", dayIndex: 2, session: .goldenMorning),
        .init(spotID: "mono-lake-south-tufa", dayIndex: 2, session: .goldenEvening),
    ])

    static let yosemite = TripTemplate(id: "yosemite", defaultName: "Yosemite", dayCount: 2, stops: [
        .init(spotID: "tunnel-view", dayIndex: 0, session: .goldenEvening),
        .init(spotID: "valley-view", dayIndex: 1, session: .goldenMorning),
        .init(spotID: "glacier-point", dayIndex: 1, session: .goldenEvening),
    ])
}
