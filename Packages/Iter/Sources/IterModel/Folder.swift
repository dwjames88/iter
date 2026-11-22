import Foundation

/// What a folder holds. Raw values are stored.
public enum FolderKind: String, Codable, CaseIterable, Hashable, Sendable {
    case trips, locations
}

/// A user folder for trips or locations. Folders are one level deep: nothing nests.
public struct Folder: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var kind: FolderKind
    public var sortOrder: Double
    /// Default `.distantPast`: this target never reads the clock, so callers stamp real dates.
    public var createdAt: Date
    public var updatedAt: Date
    public var isPinned: Bool
    public var pinnedAt: Date?

    public init(id: UUID = UUID(), name: String, kind: FolderKind = .trips, sortOrder: Double = 0, createdAt: Date = .distantPast,
                updatedAt: Date = .distantPast, isPinned: Bool = false, pinnedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isPinned = isPinned
        self.pinnedAt = pinnedAt
    }

    private enum CodingKeys: String, CodingKey { case id, name, kind, sortOrder, createdAt, updatedAt, isPinned, pinnedAt }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        kind = try c.decodeIfPresent(FolderKind.self, forKey: .kind) ?? .trips
        sortOrder = try c.decodeIfPresent(Double.self, forKey: .sortOrder) ?? 0
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? .distantPast
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .distantPast
        isPinned = try c.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        pinnedAt = try c.decodeIfPresent(Date.self, forKey: .pinnedAt)
    }
}
