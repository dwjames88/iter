import Foundation
import SwiftData

/// The file operations the opener performs, behind a protocol so a test can make one fail part way through a backup.
public protocol StoreFileOperations: Sendable {
    func fileExists(at url: URL) -> Bool
    func createDirectory(at url: URL) throws
    func copyItem(at source: URL, to destination: URL) throws
    func moveItem(at source: URL, to destination: URL) throws
    func removeItem(at url: URL) throws
    func contentsOfDirectory(at url: URL) throws -> [URL]
    func write(_ data: Data, to url: URL) throws
    func read(_ url: URL) throws -> Data
    /// The size in bytes of a file (for a folder, any value: callers only compare files).
    func fileSize(at url: URL) throws -> Int
}

/// `FileManager.default`.
public struct DefaultStoreFileOperations: StoreFileOperations {
    public init() {}

    public func fileExists(at url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }
    public func createDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
    public func copyItem(at source: URL, to destination: URL) throws {
        try FileManager.default.copyItem(at: source, to: destination)
    }
    public func moveItem(at source: URL, to destination: URL) throws {
        try FileManager.default.moveItem(at: source, to: destination)
    }
    public func removeItem(at url: URL) throws { try FileManager.default.removeItem(at: url) }
    public func contentsOfDirectory(at url: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
    }
    public func write(_ data: Data, to url: URL) throws { try data.write(to: url, options: .atomic) }
    public func read(_ url: URL) throws -> Data { try Data(contentsOf: url) }
    public func fileSize(at url: URL) throws -> Int {
        (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
    }
}

/// How the opener builds containers, so a test can make the V5 open or the scratch open fail.
public struct StoreContainerFactory: Sendable {
    /// Opens (and migrates to V5) the store at a URL.
    public var openCurrent: @Sendable (URL) throws -> ModelContainer
    /// Opens a scratch copy on the frozen V4 schema, migrating V1 to V3 stores up to V4 and no further.
    public var openLegacyV4: @Sendable (URL) throws -> ModelContainer

    public init(openCurrent: @escaping @Sendable (URL) throws -> ModelContainer,
                openLegacyV4: @escaping @Sendable (URL) throws -> ModelContainer) {
        self.openCurrent = openCurrent
        self.openLegacyV4 = openLegacyV4
    }

    public static let live = StoreContainerFactory(
        openCurrent: { try IterStoreSchema.makeContainer(url: $0) },
        openLegacyV4: { try IterStoreSchema.makeLegacyV4Container(url: $0) })
}
