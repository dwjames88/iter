import Foundation
import IterFeatures

/// How the iPhone's All Trips list is sectioned: the next trip as the hero, Pinned, then (at the top level) the folders as rows and
/// the trips that are in none, or (inside a folder) every trip the folder holds. Pure, so tests check it.
public struct PhoneTripSections: Equatable, Sendable {
    public var hero: TripRow?
    public var pinned: [TripRow]
    public var folders: [FolderRow]
    public var trips: [TripRow]

    public var isEmpty: Bool { hero == nil && pinned.isEmpty && trips.isEmpty && folders.isEmpty }

    public static func make(trips all: [TripRow], next: TripRow?, folders: [FolderRow], folderID: UUID?) -> PhoneTripSections {
        guard let folderID else {
            let rest = all.filter { $0.id != next?.id }
            return PhoneTripSections(hero: next, pinned: rest.filter(\.isPinned), folders: folders,
                                     trips: rest.filter { !$0.isPinned && $0.folderID == nil })
        }
        let inFolder = all.filter { $0.folderID == folderID }
        return PhoneTripSections(hero: nil, pinned: inFolder.filter(\.isPinned), folders: [], trips: inFolder.filter { !$0.isPinned })
    }
}

/// The same for Saved Places: pinned places, then folders as rows, then the places in no folder (or all of a folder's).
public struct PhonePlaceSections: Equatable, Sendable {
    public var pinned: [PlaceRow]
    public var folders: [FolderRow]
    public var places: [PlaceRow]

    public static func make(places all: [PlaceRow], folders: [FolderRow], folderID: UUID?) -> PhonePlaceSections {
        guard let folderID else {
            return PhonePlaceSections(pinned: all.filter(\.isPinned), folders: folders, places: all.filter { !$0.isPinned && $0.folderID == nil })
        }
        let inFolder = all.filter { $0.folderID == folderID }
        return PhonePlaceSections(pinned: inFolder.filter(\.isPinned), folders: [], places: inFolder.filter { !$0.isPinned })
    }
}
