import SwiftUI
import Testing
import IterFeatures
import IterModel
@testable import IterScreens

/// Library screens and sheets rendered offscreen: an in-memory library (seeded with `SampleLibrary.seed` where a populated state
/// is wanted) under the package test container's fixed clock. Glass and MapKit do not draw offscreen.
@MainActor @Suite(.serialized) struct LibrarySnapshotTests {
    private static let denver = TimeZone(identifier: "America/Denver") ?? .current

    private func container(seed: Bool) throws -> (AppContainer, LibraryModel) {
        let c = try AppContainer.test(seed: seed)
        return (c, c.libraryModel(timeZone: Self.denver))
    }

    private func wrap<V: View>(_ view: V) -> some View {
        view
            .environment(AppNavigator())
            .environment(\.libraryClock, { AppContainer.testNow })
    }

    @Test func allTripsEmpty() async throws {
        let (_, library) = try container(seed: false)
        try await Snapshot.record(wrap(AllTripsScreen(library: library)), name: "all-trips-empty", size: CGSize(width: 1000, height: 820))
    }

    @Test func allTripsPopulated() async throws {
        let (_, library) = try container(seed: true)
        try await Snapshot.record(wrap(AllTripsScreen(library: library).environment(\.libraryLightScore, { _, _, _ in 88 })),
                                  name: "all-trips-populated", size: CGSize(width: 1000, height: 820))
    }

    @Test func allTripsFolder() async throws {
        let (c, library) = try container(seed: true)
        let folder = library.tripFolders.first
        _ = c
        try await Snapshot.record(wrap(AllTripsScreen(library: library, folderID: folder?.id)), name: "all-trips-folder",
                                  size: CGSize(width: 1000, height: 520))
    }

    @Test func savedPlaces() async throws {
        let (_, library) = try container(seed: true)
        try await Snapshot.record(wrap(SavedPlacesList(library: library, folderID: nil, selected: .constant(library.savedPlaces.first?.id))
            .frame(width: 400).background(IterColorBackdrop())), name: "saved-places", size: CGSize(width: 440, height: 760))
    }

    @Test func savedPlacesFolder() async throws {
        let (_, library) = try container(seed: true)
        let folder = library.placeFolders.first
        try await Snapshot.record(wrap(SavedPlacesList(library: library, folderID: folder?.id, selected: .constant(nil))
            .frame(width: 400).background(IterColorBackdrop())), name: "saved-places-folder", size: CGSize(width: 440, height: 520))
    }

    @Test func newTripTemplateSheet() async throws {
        let (_, library) = try container(seed: false)
        let tomorrow = LocalDay(year: 2027, month: 3, day: 11)
        try await Snapshot.record(wrap(NewTripForm(library: library, templateID: "canyon-country", firstPlace: nil, onCreated: { _ in }, tomorrow: tomorrow)),
                                  name: "sheet-new-trip-template", size: CGSize(width: 560, height: 440))
    }

    @Test func changeDatesWarning() async throws {
        let model = BuildPreviewData.canyonCountry(.ready)
        try await Snapshot.record(wrap(ChangeDatesForm(model: model, dayCount: 2)), name: "sheet-change-dates-warning",
                                  size: CGSize(width: 560, height: 360))
    }

    @Test func placeEditorOwnSpot() async throws {
        let (_, library) = try container(seed: true)
        let id = library.createPlace(name: "Lone Pine Overlook", locality: "Lone Pine, CA",
                                     coordinate: Coordinate(latitude: 36.5786, longitude: -118.2920),
                                     timeZoneIdentifier: "America/Los_Angeles", category: .landscape, notes: "Park at the pullout.")
        try await Snapshot.record(wrap(PlaceEditorSheet(library: library, placeID: id)), name: "sheet-place-editor-own-spot",
                                  size: CGSize(width: 560, height: 980))
    }
}

private struct IterColorBackdrop: View {
    var body: some View { Color(white: 0.5, opacity: 0.0) }
}

@Suite struct CoordinateTextTests {
    @Test func parsesPairs() {
        #expect(CoordinateText.parse("36.5786, -118.2920") == Coordinate(latitude: 36.5786, longitude: -118.2920))
        #expect(CoordinateText.parse("36.5786 -118.2920") != nil)
        #expect(CoordinateText.parse("91, 10") == nil)
        #expect(CoordinateText.parse("hello") == nil)
        #expect(CoordinateText.parse("1,2,3") == nil)
    }
}
