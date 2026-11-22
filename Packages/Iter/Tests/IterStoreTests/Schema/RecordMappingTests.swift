import Foundation
import SwiftData
import Testing
import IterModel
@testable import IterStore

@Suite struct RecordMappingTests {
    let context: ModelContext
    init() throws { context = ModelContext(try IterStoreSchema.makeInMemoryContainer()) }

    func place(_ name: String) -> Place {
        Place(name: name, locality: "L", coordinate: Coordinate(latitude: 1.5, longitude: -2.5), timeZoneIdentifier: "America/Denver",
              category: .astro, bestLight: [.night, .sunrise], facing: 90, blurb: "b", notes: "n", walkInMinutes: 5,
              elevationMeters: 100, popularity: 70, tags: ["a", "b"], origin: .scout, isSaved: true, sortOrder: 3,
              isPinned: true, pinnedAt: Date(timeIntervalSinceReferenceDate: 10),
              createdAt: Date(timeIntervalSinceReferenceDate: 1), updatedAt: Date(timeIntervalSinceReferenceDate: 2),
              sources: ["apple.mapkit", "osm"],
              citations: [Citation(source: "osm", url: URL(string: "https://osm.org/x"), title: "T", retrievedAt: Date(timeIntervalSince1970: 100))],
              verification: .confirmed, discoveredAt: Date(timeIntervalSinceReferenceDate: 4),
              horizon: HorizonProfile(elevationsDegrees: [1, 2, 3]))
    }

    @Test func placeRoundTrips() {
        let value = place("Roundtrip")
        let record = PlaceRecord(id: value.id)
        record.apply(value)
        #expect(record.value() == value)
        #expect(record.verificationRaw == "confirmed" && record.sourcesRaw == "apple.mapkit,osm")
    }

    @Test func placeWithNoProvenanceHasEmptyV5Columns() {
        var value = place("Plain")
        value.sources = []; value.citations = []; value.verification = nil; value.discoveredAt = nil; value.horizon = nil
        let record = PlaceRecord(id: value.id)
        record.apply(value)
        #expect(record.sourcesRaw == "" && record.citationsJSON == "" && record.verificationRaw == "" && record.horizonJSON == "")
        #expect(record.value() == value)
    }

    @Test func folderRoundTrips() {
        let value = Folder(name: "F", kind: .locations, sortOrder: 2, createdAt: Date(timeIntervalSinceReferenceDate: 1),
                           updatedAt: Date(timeIntervalSinceReferenceDate: 2), isPinned: true, pinnedAt: Date(timeIntervalSinceReferenceDate: 3))
        let record = FolderRecord(id: value.id)
        record.apply(value)
        #expect(record.value() == value)
    }

    @Test func tripRoundTripsWithStopsInOrderAndDropsAStopWithoutAPlace() throws {
        let p1 = place("One"), p2 = place("Two")
        let stopA = Stop(place: p1, dayIndex: 1, session: .night, setUpBufferMinutes: 5, note: "a", driveNote: "d",
                         dwellMinutes: 45, fixedArrival: LocalTime(hour: 19, minute: 30), kind: .lodging)
        let stopB = Stop(place: p2, dayIndex: 0, session: .goldenMorning)
        let stopC = Stop(place: p2, dayIndex: 1, session: .blueEvening)
        let trip = Trip(name: "T", startDay: LocalDay(year: 2026, month: 10, day: 10), dayCount: 3, stops: [stopB, stopA, stopC],
                        notes: "N", transferTimings: [1: .eveningBefore, 2: .morning], sortOrder: 4, isPinned: true,
                        pinnedAt: Date(timeIntervalSinceReferenceDate: 7), createdAt: Date(timeIntervalSinceReferenceDate: 1),
                        updatedAt: Date(timeIntervalSinceReferenceDate: 2), startPlaceID: p1.id)
        let record = TripRecord(id: trip.id)
        context.insert(record)
        record.apply(trip)
        #expect(record.transferTimingsRaw == "1:eveningBefore")
        var records: [UUID: PlaceRecord] = [:]
        for (i, stop) in trip.stops.enumerated() {
            let pr = records[stop.place.id] ?? { let r = PlaceRecord(id: stop.place.id); r.apply(stop.place); context.insert(r); return r }()
            records[stop.place.id] = pr
            let sr = StopRecord(id: stop.id)
            context.insert(sr)
            sr.apply(stop, sortOrder: Double(i))
            sr.trip = record
            sr.place = pr
        }
        // A stop with a broken place link is left out of the value.
        let broken = StopRecord()
        context.insert(broken)
        broken.trip = record
        broken.dayIndex = 0
        try context.save()

        let back = record.value()
        // Day-major order: day 0 first, then day 1 by sortOrder (A was written at index 1, C at 2).
        #expect(back.stops.map(\.id) == [stopB.id, stopA.id, stopC.id])
        #expect(back.stops[1] == stopA)
        #expect(back.transferTimings == [1: .eveningBefore])
        #expect(back.startPlaceID == p1.id && back.timeZonePolicy == .spot)
        #expect(back.sortOrder == 4 && back.isPinned && back.pinnedAt == trip.pinnedAt)
    }

    @Test func orderingTieBreaksOnIDLikeTheOldCode() {
        let record = TripRecord()
        context.insert(record)
        let ids = [UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!, UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!]
        for id in ids {
            let s = StopRecord(id: id)
            context.insert(s)
            s.trip = record
        }
        #expect(record.orderedStops.map(\.id) == ids.sorted { $0.uuidString < $1.uuidString })
    }

    @Test(arguments: [("", [:]), ("1:eveningBefore", [1: TransferTiming.eveningBefore]), ("0:eveningBefore", [:]), ("3:eveningBefore", [:]),
                      ("1:morning", [:]), ("x:eveningBefore", [:]), ("2:bogus", [:]), ("1:eveningBefore,2:eveningBefore", [1: .eveningBefore, 2: .eveningBefore])])
    func transferTimingRulesMatchTheOldParser(raw: String, expected: [Int: TransferTiming]) {
        #expect(TransferTimingsCodec.parse(raw, dayCount: 3) == expected)
    }

    @Test func unknownRawValuesFallBackLikeTheOldAccessors() {
        let record = PlaceRecord()
        record.originRaw = "???"; record.categoryRaw = "???"; record.bestLightRaw = "night,???,sunrise"; record.tagsRaw = ""
        let value = record.value()
        #expect(value.origin == .user && value.category == .landscape && value.bestLight == [.night, .sunrise] && value.tags.isEmpty)
        let stop = StopRecord()
        stop.sessionRaw = "???"; stop.kindRaw = "???"; stop.fixedArrivalISO = "9:5"
        stop.place = record
        let sv = stop.value()
        #expect(sv?.session == .goldenEvening && sv?.kind == .light && sv?.fixedArrival == nil)
    }
}
