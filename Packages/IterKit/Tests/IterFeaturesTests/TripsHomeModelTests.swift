import Foundation
import Testing
import IterCore
import IterLight
import IterData
@testable import IterFeatures

@MainActor
@Suite struct TripsHomeModelTests {
    private func home(_ h: TripHarness, at date: Date) -> TripsHomeModel {
        TripsHomeModel(store: h.store, engine: h.scheduler.engine, now: { date })
    }

    private var beforeTrip: Date { LocalDay(year: 2026, month: 10, day: 6).at(hour: 10, in: TripHarness.denver) }

    @Test func nextSessionIsTheFirstStopThatHasNotEnded() {
        let h = TripHarness()
        _ = h.makeTrip()
        let before = home(h, at: beforeTrip).summaries()[0]
        #expect(before.stopCount == 3)
        #expect(before.dayCount == 2)
        #expect(before.next?.spotName == "Mesa Arch")
        #expect(before.next?.kind == .goldenMorning)
        #expect(before.next?.day == TripHarness.start)

        // After day 1's sunrise window has ended the next one is Delicate Arch's sunset.
        let noon = TripHarness.start.at(hour: 12, in: TripHarness.denver)
        #expect(home(h, at: noon).summaries()[0].next?.spotName == "Delicate Arch")
        // After everything: none.
        let later = TripHarness.start.adding(days: 5).at(hour: 12, in: TripHarness.denver)
        #expect(home(h, at: later).summaries()[0].next == nil)
        #expect(before.endDay == TripHarness.start.adding(days: 1))
    }

    @Test func tripWithoutStopsHasNoNextSession() {
        let h = TripHarness()
        _ = h.store.createTrip(name: "Empty", startDay: TripHarness.start, dayCount: 2)
        let summary = home(h, at: beforeTrip).summaries()[0]
        #expect(summary.stopCount == 0)
        #expect(summary.next == nil)
    }

    @Test func createFromDraft() {
        let h = TripHarness()
        let model = home(h, at: beforeTrip)
        let plain = model.create(NewTripDraft(startDay: TripHarness.start, dayCount: 4, name: "  Utah  "), fallbackName: "New Trip")
        #expect(plain.name == "Utah")
        #expect(plain.dayCount == 4)
        let blank = model.create(NewTripDraft(startDay: TripHarness.start, dayCount: 2), fallbackName: "New Trip")
        #expect(blank.name == "New Trip")
        let templated = model.create(NewTripDraft(startDay: TripHarness.start, dayCount: 9, templateID: "yosemite"), fallbackName: "New Trip")
        #expect(templated.name == "Yosemite")
        #expect(templated.dayCount == 2)
        #expect(templated.orderedStops.count == 3)
        let renamed = model.create(NewTripDraft(startDay: TripHarness.start, templateID: "yosemite", name: "Valley weekend"), fallbackName: "New Trip")
        #expect(renamed.name == "Valley weekend")
        #expect(NewTripDraft(startDay: TripHarness.start, dayCount: 9, templateID: "yosemite").effectiveDayCount == 2)
    }

    @Test func importRoundTripAndErrors() throws {
        let h = TripHarness()
        let source = h.makeTrip()
        let data = try h.store.document(for: source).encoded()
        let model = home(h, at: beforeTrip)

        let result = model.importTrip(from: data)
        let id = try result.get()
        #expect(id != source.id)
        #expect(h.store.trip(id: id)?.orderedStops.count == 3)

        let before = h.store.trips().count
        #expect(model.importTrip(from: Data("not json".utf8)) == .failure(.corrupt))
        #expect(model.importTrip(from: Data("{\"formatVersion\": 1}".utf8)) == .failure(.corrupt))
        #expect(model.importTrip(from: Data("{\"formatVersion\": 99}".utf8)) == .failure(.unsupportedVersion(99)))
        #expect(model.importTrip(contentsOf: URL(fileURLWithPath: "/nonexistent/trip.iter")) == .failure(.unreadable))
        #expect(h.store.trips().count == before, "a failed import changes nothing")
    }
}
