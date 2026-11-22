import Foundation
import Testing
import IterCore
import IterData
@testable import IterFeatures

/// The place card's buttons call these; each test is "the button's action ran and the store changed".
@MainActor
@Suite struct PlaceCardActionsTests {
    final class Recorder { var opened: [String] = [] }

    private func make() throws -> (PlaceCardActions, IterStore, Recorder) {
        let store = IterStore(container: try IterSchema.makeContainer(inMemory: true))
        let recorder = Recorder()
        let actions = PlaceCardActions(store: store,
                                       tomorrow: { _ in LocalDay(year: 2026, month: 10, day: 10) },
                                       openInMaps: { recorder.opened.append($0.id) })
        return (actions, store, recorder)
    }

    private let mesa = CuratedSpots.spot(id: "mesa-arch")!

    @Test func saveTogglesAndPersistsInTheStore() throws {
        let (actions, store, _) = try make()
        #expect(!actions.isSaved(mesa))
        #expect(actions.toggleSaved(mesa))
        #expect(store.isSaved(spotID: mesa.id))
        #expect(!actions.toggleSaved(mesa))
        #expect(!store.isSaved(spotID: mesa.id))
    }

    @Test func addToTripPutsTheSpotOnTheChosenDay() throws {
        let (actions, store, _) = try make()
        let trip = store.createTrip(name: "Utah", startDay: LocalDay(year: 2026, month: 10, day: 7), dayCount: 3)
        let added = actions.add(mesa, to: trip, day: 1)
        #expect(added == PlaceCardActions.Added(tripID: trip.id, tripName: "Utah", dayNumber: 2, isNewTrip: false))
        #expect(trip.orderedStops(onDay: 1).count == 1)
        #expect(trip.orderedStops(onDay: 0).isEmpty)
    }

    @Test func addToNewTripMakesTheTripStartingTomorrow() throws {
        let (actions, store, _) = try make()
        let added = actions.addToNewTrip(mesa, name: "Trip to Mesa Arch")
        #expect(added.isNewTrip && added.dayNumber == 1)
        let trip = try #require(store.trip(id: added.tripID))
        #expect(trip.name == "Trip to Mesa Arch")
        #expect(trip.startDay == LocalDay(year: 2026, month: 10, day: 10))
        #expect(trip.orderedStops(onDay: 0).count == 1)
        #expect(store.trips().count == 1)
    }

    @Test func confirmationNamesTheTripAndDay() throws {
        let added = PlaceCardActions.Added(tripID: UUID(), tripName: "Utah", dayNumber: 2, isNewTrip: false)
        #expect(added.message.contains("Utah") && added.message.contains("2"))
    }

    @Test func openInMapsCallsTheHandlerWithTheSpot() throws {
        let (actions, _, recorder) = try make()
        actions.openInMaps(mesa)
        #expect(recorder.opened == ["mesa-arch"])
    }
}
