import Foundation
import Testing
@testable import IterFeatures

@Suite struct LibraryTests {
    @Test func uniqueNamesCountUp() {
        #expect(LibraryNaming.uniqueName("New Folder", among: []) == "New Folder")
        #expect(LibraryNaming.uniqueName("New Folder", among: ["Coast"]) == "New Folder")
        #expect(LibraryNaming.uniqueName("New Folder", among: ["New Folder"]) == "New Folder 2")
        #expect(LibraryNaming.uniqueName("New Folder", among: ["new folder", "New Folder 2"]) == "New Folder 3")
    }

    @Test func cleanedNameRejectsEmpty() {
        #expect(LibraryNaming.cleanedName("  ") == nil)
        #expect(LibraryNaming.cleanedName("") == nil)
        #expect(LibraryNaming.cleanedName("  Coast \n") == "Coast")
    }

    @Test func dragItemRoundTripsThroughJSON() throws {
        let id = UUID()
        for item in [LibraryDragItem.trip(id), .place(id), .folder(id)] {
            let data = try JSONEncoder().encode(item)
            #expect(try JSONDecoder().decode(LibraryDragItem.self, from: data) == item)
        }
        #expect(LibraryDragItem.trip(id).tripID == id)
        #expect(LibraryDragItem.trip(id).placeID == nil)
        #expect(LibraryDragItem.folder(id).folderID == id)
    }
}
