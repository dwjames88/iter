import Foundation
import SwiftData

/// The tombstones that tell a sync merge "this was deleted". Deleting a trip, place or folder writes one (through the
/// other repositories); undoing the delete removes it.
@MainActor
public struct DeletionRepository {
    /// How long a tombstone is kept: 90 days.
    public static let retention: TimeInterval = 90 * 24 * 3600

    unowned let store: LibraryStore

    /// Every tombstone as a value, newest first.
    public func all() -> [LibraryTombstone] {
        records().sorted { ($0.deletedAt, $0.id.uuidString) > ($1.deletedAt, $1.id.uuidString) }
            .compactMap { record in
                LibraryTombstone.Entity(rawValue: record.entityRaw).map {
                    LibraryTombstone(entity: $0, id: record.entityID, deletedAt: record.deletedAt)
                }
            }
    }

    public func tombstone(_ entity: LibraryTombstone.Entity, id: UUID) -> LibraryTombstone? {
        store.tombstoneRecord(TombstoneKey(entityRaw: entity.rawValue, entityID: id))
            .map { LibraryTombstone(entity: entity, id: id, deletedAt: $0.deletedAt) }
    }

    /// Removes the tombstones older than `age` before now. Not undoable. Returns how many went.
    @discardableResult
    public func prune(olderThan age: TimeInterval = DeletionRepository.retention) -> Int {
        let cutoff = store.clock().addingTimeInterval(-age)
        let old = records().filter { $0.deletedAt < cutoff }
        guard !old.isEmpty else { return 0 }
        for record in old { store.context.delete(record) }
        store.didChange()
        return old.count
    }

    private func records() -> [DeletionRecord] {
        (try? store.context.fetch(FetchDescriptor<DeletionRecord>())) ?? []
    }
}
