import Foundation
import SwiftData

/// Folders used to nest one level. `flattenFolders` (run on every open) makes every folder top level.
public enum FolderFlatten {
    /// Folders ordered by (sort order, name, id), the old `folderOrder`.
    static func folderOrder(_ a: FolderRecord, _ b: FolderRecord) -> Bool {
        if a.sortOrder != b.sortOrder { return a.sortOrder < b.sortOrder }
        switch a.name.localizedStandardCompare(b.name) {
        case .orderedAscending: return true
        case .orderedDescending: return false
        case .orderedSame: return a.id.uuidString < b.id.uuidString
        }
    }

    /// One-time fixup, run when the store opens: each nested folder keeps its name, kind, pin, trips and places, loses
    /// its parent, and is placed right after its former parent (its former siblings keep their relative order); each
    /// kind is then renumbered 0, 1, 2... Folders of the same name are never merged. Idempotent: with nothing nested it
    /// changes nothing (and does not save). Flattened folders get `updatedAt = now`. Returns how many were flattened.
    @discardableResult
    public static func flattenFolders(in context: ModelContext, now: Date = .now) throws -> Int {
        let all = try context.fetch(FetchDescriptor<FolderRecord>())
        let nested = all.filter { $0.parent != nil }
        guard !nested.isEmpty else { return 0 }
        for kind in ["trips", "locations"] {
            // An unknown raw kind reads as trips, as the old `kind` accessor did.
            let ofKind = all.filter { ($0.kindRaw == "locations" ? "locations" : "trips") == kind }
            var ordered: [FolderRecord] = []
            var seen = Set<UUID>()
            func visit(_ folder: FolderRecord) {
                guard seen.insert(folder.id).inserted else { return }
                ordered.append(folder)
                for child in ofKind.filter({ $0.parent?.id == folder.id }).sorted(by: folderOrder) { visit(child) }
            }
            for root in ofKind.filter({ $0.parent == nil }).sorted(by: folderOrder) { visit(root) }
            // Anything left over (a corrupt parent cycle) goes at the end.
            for folder in ofKind.sorted(by: folderOrder) { visit(folder) }
            for (i, folder) in ordered.enumerated() where folder.sortOrder != Double(i) {
                folder.sortOrder = Double(i)
            }
        }
        for folder in nested {
            folder.parent = nil
            folder.updatedAt = now
        }
        try context.save()
        return nested.count
    }
}
