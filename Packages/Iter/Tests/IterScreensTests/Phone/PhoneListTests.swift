import Foundation
import Testing
import IterModel
@testable import IterFeatures
@testable import IterScreens

/// The iPhone lists' sectioning and the Undo toast, on the in-memory sample library.
@MainActor @Suite(.serialized) struct PhoneListTests {
    private func row(_ name: String, day: Int, pinned: Bool = false, folder: UUID? = nil) -> TripRow {
        TripRow(id: UUID(), name: name, startDay: LocalDay(year: 2027, month: 3, day: day), dayCount: 2, stopCount: 1, placeNames: [],
                folderID: folder, isPinned: pinned, updatedAt: Date(timeIntervalSince1970: 0))
    }

    @Test func topLevelSectionsKeepHeroPinnedAndFolderedApart() {
        let folderID = UUID()
        let folder = FolderRow(id: folderID, name: "Utah", kind: .trips, count: 1, isPinned: false)
        let hero = row("Next", day: 1), pinned = row("Pinned", day: 2, pinned: true), loose = row("Loose", day: 3)
        let filed = row("Filed", day: 4, folder: folderID)
        let s = PhoneTripSections.make(trips: [hero, pinned, loose, filed], next: hero, folders: [folder], folderID: nil)
        #expect(s.hero?.id == hero.id)
        #expect(s.pinned.map(\.name) == ["Pinned"])
        #expect(s.folders.map(\.name) == ["Utah"])
        #expect(s.trips.map(\.name) == ["Loose"])
    }

    @Test func folderSectionsShowEveryTripOfTheFolder() {
        let folderID = UUID()
        let a = row("A", day: 1, pinned: true, folder: folderID), b = row("B", day: 2, folder: folderID), other = row("Other", day: 3)
        let s = PhoneTripSections.make(trips: [a, b, other], next: other, folders: [], folderID: folderID)
        #expect(s.hero == nil)
        #expect(s.pinned.map(\.name) == ["A"])
        #expect(s.trips.map(\.name) == ["B"])
        #expect(s.folders.isEmpty)
    }

    @Test func emptyLibraryHasNoSections() {
        #expect(PhoneTripSections.make(trips: [], next: nil, folders: [], folderID: nil).isEmpty)
        #expect(PhonePlaceSections.make(places: [], folders: [], folderID: nil).pinned.isEmpty)
    }

    @Test func sampleLibrarySectionsAddUp() throws {
        let c = try AppContainer.test(seed: true)
        let library = c.libraryModel()
        let s = PhoneTripSections.make(trips: library.trips, next: library.nextTrip, folders: library.tripFolders, folderID: nil)
        let shown = (s.hero.map { [$0] } ?? []) + s.pinned + s.trips
        let filed = library.trips.filter { $0.folderID != nil && !$0.isPinned && $0.id != library.nextTrip?.id }
        #expect(shown.count + filed.count == library.trips.count)
        #expect(Set(shown.map(\.id)).count == shown.count)
        let places = PhonePlaceSections.make(places: library.savedPlaces, folders: library.placeFolders, folderID: nil)
        #expect(places.pinned.allSatisfy { $0.isPinned })
        #expect(places.places.allSatisfy { $0.folderID == nil && !$0.isPinned })
    }

    @Test func deleteThenUndoBringsTheTripBack() throws {
        let c = try AppContainer.test(seed: true)
        let library = c.libraryModel()
        let toast = PhoneUndoToast(library: library, lifetime: .seconds(60))
        let manager = try #require(library.undoManager)
        manager.groupsByEvent = false
        let id = try #require(library.trips.first?.id)
        let before = library.trips.count
        toast.perform("Trip Deleted") { library.deleteTrip(id) }
        #expect(library.trips.count == before - 1)
        #expect(toast.current?.message == "Trip Deleted")
        #expect(toast.undo())
        #expect(library.trips.count == before)
        #expect(library.tripRow(id: id) != nil)
        #expect(toast.current == nil)
    }

    @Test func undoWithNothingToUndoIsFalse() throws {
        let c = try AppContainer.test(seed: true)
        let toast = PhoneUndoToast(library: c.libraryModel())
        #expect(!toast.undo())
    }

    @Test func toastDismissesItself() async throws {
        let c = try AppContainer.test(seed: true)
        let toast = PhoneUndoToast(library: c.libraryModel(), lifetime: .milliseconds(30))
        toast.show("Place Removed")
        #expect(toast.current != nil)
        try await Task.sleep(for: .milliseconds(300))
        #expect(toast.current == nil)
    }
}
