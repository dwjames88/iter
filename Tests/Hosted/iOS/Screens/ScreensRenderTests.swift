import SwiftUI
import Testing
import IterFeatures
import IterModel
import IterScreens
@testable import Iter

/// The iPhone sheet screens and the iPad detail, rendered light and dark. Glass, MapKit tiles and pins do not draw offscreen.
@MainActor @Suite(.serialized) struct ScreensRenderTests {
    private func check(_ images: [CGImage]) {
        #expect(images.count == 2)
        for image in images { #expect(!ScreensHarness.isBlank(image)) }
    }

    // MARK: Find

    @Test func findIdle() async throws {
        let shell = try ScreensHarness.shell(find: try await FindPreviewData.model(.empty))
        check(try await ScreensHarness.render(ScreensHarness.sheet(shell) { FindTabRoot(shell: shell) },
                                              name: "find-idle-half", size: ScreensHarness.phoneHalf))
    }

    @Test func findSearching() async throws {
        let shell = try ScreensHarness.shell(find: try await FindPreviewData.model(.searching))
        check(try await ScreensHarness.render(ScreensHarness.sheet(shell) { FindTabRoot(shell: shell) },
                                              name: "find-searching-full", size: ScreensHarness.phoneFull))
    }

    @Test func findResults() async throws {
        let shell = try ScreensHarness.shell(find: try await FindPreviewData.model(.results))
        check(try await ScreensHarness.render(ScreensHarness.sheet(shell) { FindTabRoot(shell: shell) },
                                              name: "find-results-full", size: ScreensHarness.phoneFull))
        check(try await ScreensHarness.render(ScreensHarness.sheet(shell) { FindTabRoot(shell: shell) },
                                              name: "find-results-half", size: ScreensHarness.phoneHalf))
    }

    @Test func findPlaceCard() async throws {
        let find = try await FindPreviewData.model(.results)
        if let first = find.rows.first { find.select(first.id) }
        let shell = try ScreensHarness.shell(find: find)
        check(try await ScreensHarness.render(ScreensHarness.sheet(shell) { FindTabRoot(shell: shell) },
                                              name: "find-place-card-full", size: ScreensHarness.phoneFull))
    }

    @Test func findAddTargetBanner() async throws {
        let find = try await FindPreviewData.model(.results)
        if let first = find.rows.first { find.select(first.id) }
        let shell = try ScreensHarness.shell(find: find)
        FindAddTarget.shared.set(tripID: try #require(shell.library.trips.first?.id), day: 1)
        defer { FindAddTarget.shared.clear() }
        check(try await ScreensHarness.render(ScreensHarness.sheet(shell) { FindTabRoot(shell: shell) },
                                              name: "find-add-target-full", size: ScreensHarness.phoneFull))
    }

    // MARK: Place page

    @Test func placePage() async throws {
        let shell = try ScreensHarness.shell()
        let id = try #require(shell.library.savedPlaces.first?.id)
        check(try await ScreensHarness.render(ScreensHarness.sheet(shell) { PhonePlaceScreen(shell: shell, placeID: id) },
                                              name: "place-page-full", size: ScreensHarness.phoneFull))
    }

    // MARK: Trips

    @Test func allTrips() async throws {
        let shell = try ScreensHarness.shell()
        check(try await ScreensHarness.render(ScreensHarness.sheet(shell) { TripsTabRoot(shell: shell) },
                                              name: "all-trips-full", size: ScreensHarness.phoneFull))
        check(try await ScreensHarness.render(ScreensHarness.sheet(shell) { TripsTabRoot(shell: shell) },
                                              name: "all-trips-half", size: ScreensHarness.phoneHalf))
    }

    @Test func tripFolder() async throws {
        let shell = try ScreensHarness.shell()
        let folder = try #require(shell.library.tripFolders.first)
        check(try await ScreensHarness.render(ScreensHarness.sheet(shell) { TripsListHost(shell: shell, folderID: folder.id) },
                                              name: "trip-folder-half", size: ScreensHarness.phoneHalf))
    }

    @Test func tripBuilder() async throws {
        let shell = try ScreensHarness.shell()
        let id = try #require(shell.library.trips.first { $0.name == "Canyon Country" }?.id ?? shell.library.trips.first?.id)
        let model = shell.buildModel(for: id)
        model.open()
        defer { model.close() }
        check(try await ScreensHarness.render(ScreensHarness.sheet(shell) { PhoneTripScreen(shell: shell, tripID: id) },
                                              name: "trip-builder-full", size: ScreensHarness.phoneFull))
        check(try await ScreensHarness.render(ScreensHarness.sheet(shell) { PhoneTripScreen(shell: shell, tripID: id) },
                                              name: "trip-builder-half", size: ScreensHarness.phoneHalf))
    }

    // MARK: Saved

    @Test func savedPlaces() async throws {
        let shell = try ScreensHarness.shell()
        check(try await ScreensHarness.render(ScreensHarness.sheet(shell) { SavedTabRoot(shell: shell) },
                                              name: "saved-places-full", size: ScreensHarness.phoneFull))
    }

    @Test func savedFolder() async throws {
        let shell = try ScreensHarness.shell()
        let folder = try #require(shell.library.placeFolders.first)
        check(try await ScreensHarness.render(ScreensHarness.sheet(shell) { SavedListHost(shell: shell, folderID: folder.id) },
                                              name: "saved-folder-half", size: ScreensHarness.phoneHalf))
    }

    // MARK: Maps (the map layer behind the sheet; tiles and pins do not draw offscreen)

    @Test func tripsMapLayer() async throws {
        let shell = try ScreensHarness.shell()
        shell.sheetHeight = 400
        check(try await ScreensHarness.render(TripsTabMap(shell: shell), name: "map-trips-overview", size: ScreensHarness.phone))
    }

    // MARK: iPad

    @Test func padAllTrips() async throws {
        let shell = try ScreensHarness.shell()
        check(try await ScreensHarness.render(NavigationStack { PadDetail(shell: shell, route: .allTrips).environment(\.isOnGlass, false) },
                                              name: "pad-all-trips", size: ScreensHarness.pad))
    }

    @Test func padFind() async throws {
        let shell = try ScreensHarness.shell(find: try await FindPreviewData.model(.results))
        check(try await ScreensHarness.render(NavigationStack { PadDetail(shell: shell, route: .find) },
                                              name: "pad-find-results", size: ScreensHarness.pad))
    }

    @Test func padTrip() async throws {
        let shell = try ScreensHarness.shell()
        let id = try #require(shell.library.trips.first?.id)
        let model = shell.buildModel(for: id)
        model.open()
        defer { model.close() }
        check(try await ScreensHarness.render(NavigationStack { PadDetail(shell: shell, route: .trip(id)) },
                                              name: "pad-trip-inspector", size: ScreensHarness.pad))
    }

    @Test func padSavedPlaces() async throws {
        let shell = try ScreensHarness.shell()
        check(try await ScreensHarness.render(NavigationStack { PadDetail(shell: shell, route: .savedPlaces) },
                                              name: "pad-saved-places", size: ScreensHarness.pad))
    }

    // MARK: Sheets (the shell presents these; here at the phone's full size)

    @Test func newTripSheet() async throws {
        let shell = try ScreensHarness.shell()
        check(try await ScreensHarness.render(NewTripSheet(library: shell.library, templateID: "canyon-country", firstPlace: nil, onCreated: { _ in })
            .iterShellEnvironment(shell), name: "sheet-new-trip", size: ScreensHarness.phone))
    }

    @Test func changeDatesSheet() async throws {
        let shell = try ScreensHarness.shell()
        let id = try #require(shell.library.trips.first?.id)
        check(try await ScreensHarness.render(ChangeDatesSheet(model: shell.buildModel(for: id)).iterShellEnvironment(shell),
                                              name: "sheet-change-dates", size: ScreensHarness.phone))
    }

    @Test func placeEditorSheet() async throws {
        let shell = try ScreensHarness.shell()
        let id = try #require(shell.library.savedPlaces.first?.id)
        check(try await ScreensHarness.render(PlaceEditorSheet(library: shell.library, placeID: id).iterShellEnvironment(shell),
                                              name: "sheet-place-editor", size: ScreensHarness.phone))
    }
}
