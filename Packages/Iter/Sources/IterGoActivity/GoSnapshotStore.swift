import Foundation

/// Where the latest `GoSnapshot` is kept so the widget extension can read it without opening the store.
public protocol GoSnapshotStoring: Sendable {
    func write(_ snapshot: GoSnapshot) throws
    /// nil when there is no snapshot, the file is corrupt, or it was written by a newer version.
    func read() -> GoSnapshot?
}

/// The snapshot as a JSON file in the shared App Group container. Writes are atomic; reads never throw.
public struct AppGroupSnapshotStore: GoSnapshotStoring {
    public static let groupIdentifier = "group.com.dwjames.iter"
    public static let fileName = "go-snapshot.json"

    public let directory: URL

    /// nil when the App Group container is not available (not signed with the group, or a unit-test host).
    public init?(groupIdentifier: String = AppGroupSnapshotStore.groupIdentifier) {
        guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier) else { return nil }
        self.directory = url
    }

    /// For tests: any directory.
    public init(directory: URL) { self.directory = directory }

    public var fileURL: URL { directory.appendingPathComponent(Self.fileName) }

    public func write(_ snapshot: GoSnapshot) throws {
        let data = try JSONEncoder().encode(snapshot)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }

    public func read() -> GoSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        struct Probe: Decodable { var version: Int }
        guard let probe = try? JSONDecoder().decode(Probe.self, from: data), probe.version <= GoSnapshot.currentVersion else { return nil }
        return try? JSONDecoder().decode(GoSnapshot.self, from: data)
    }
}

/// Keeps the snapshot in memory: tests, previews.
public final class InMemorySnapshotStore: GoSnapshotStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var snapshot: GoSnapshot?
    private var writes = 0
    public var writeCount: Int { lock.withLock { writes } }

    public init(_ snapshot: GoSnapshot? = nil) { self.snapshot = snapshot }

    public func write(_ s: GoSnapshot) throws {
        lock.withLock {
            snapshot = s
            writes += 1
        }
    }

    public func read() -> GoSnapshot? { lock.withLock { snapshot } }
}
