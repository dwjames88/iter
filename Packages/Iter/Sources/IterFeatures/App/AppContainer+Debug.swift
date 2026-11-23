import Foundation
import IterModel
import IterStore
import SwiftData

/// Debug-menu support. Both refuse the owner's real store, whatever the caller thinks it is doing.
public enum DebugActionError: Error, Equatable {
    case refusedOnRealStore
}

extension AppContainer {
    /// True when this container's store is the owner's (or lives in the real store's folder).
    var storeIsReal: Bool {
        guard case .file(let url) = store.placement else { return false }
        let real = Self.defaultRealStoreURL.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath().path
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        return path == real || path.hasPrefix(real + "/")
    }

    /// Deletes every trip, place, folder and deletion record. In-memory and scratch stores only.
    /// - Throws: `DebugActionError.refusedOnRealStore` for the real store; nothing is touched.
    public func resetLibrary() throws {
        guard !storeIsReal else { throw DebugActionError.refusedOnRealStore }
        // Through the repositories so the revision moves and models refresh; no undo for a reset.
        let previous = library.undoManager
        library.undoManager = nil
        defer { library.undoManager = previous }
        for trip in library.trips.all() { library.trips.delete(trip) }
        for place in library.places.savedPlaces() { library.places.deletePlace(place) }
        for kind in FolderKind.allCases { for folder in library.folders.list(kind: kind) { library.folders.delete(folder) } }
        // Places only used by trips (not saved) were pruned with their last stop; leftover records are removed here.
        for record in (try? library.context.fetch(FetchDescriptor<PlaceRecord>())) ?? [] { library.context.delete(record) }
        for record in (try? library.context.fetch(FetchDescriptor<DeletionRecord>())) ?? [] { library.context.delete(record) }
        library.flush()
    }

    /// Adds the sample library (Canyon Country and friends). In-memory and scratch stores only.
    @discardableResult
    public func seedSampleTrip() throws -> SampleLibrary.Seeded {
        guard !storeIsReal else { throw DebugActionError.refusedOnRealStore }
        return SampleLibrary.seed(into: library, now: now())
    }
}
