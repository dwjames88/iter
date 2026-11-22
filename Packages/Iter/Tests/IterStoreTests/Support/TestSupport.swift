import Foundation
import CryptoKit
import Testing

/// Test helpers: fresh temp directories, fixture copies and file hashes. Nothing here touches the user's real stores.
enum TestSupport {
    /// A fresh directory under the system temp dir; callers remove it with `defer`.
    static func makeTempDirectory(_ label: String = "iter-store-test") throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "\(label)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// The committed fixtures folder inside the test bundle. Never open anything in it in place.
    static var fixturesRoot: URL {
        get throws {
            try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
        }
    }

    static let storeFileNames = ["Iter.store", "Iter.store-wal", "Iter.store-shm"]

    /// Copies a fixture store (`v1`, `v2`, `v3`, `v4-realistic`) to a fresh temp dir and returns the dir. The copy is the
    /// only thing a test ever opens. `storeName` renames it (iOS tests use `default.store`).
    static func copyFixtureStore(_ name: String, storeName: String = "Iter.store") throws -> URL {
        let source = try fixturesRoot.appending(path: "stores/\(name)", directoryHint: .isDirectory)
        let dir = try makeTempDirectory("iter-fixture-\(name)")
        for suffix in ["", "-wal", "-shm"] {
            let from = source.appending(path: "Iter.store" + suffix)
            guard FileManager.default.fileExists(atPath: from.path) else { continue }
            try FileManager.default.copyItem(at: from, to: dir.appending(path: storeName + suffix))
        }
        return dir
    }

    static func sha256(_ url: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
    }

    /// SHA-256 of each store file by suffix; nil for a file that does not exist.
    static func storeHashes(dir: URL, storeName: String = "Iter.store") throws -> [String: String?] {
        var out: [String: String?] = [:]
        for suffix in ["", "-wal", "-shm"] {
            let url = dir.appending(path: storeName + suffix)
            out[suffix] = FileManager.default.fileExists(atPath: url.path) ? try sha256(url) : nil
        }
        return out
    }

    static func names(in dir: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).sorted()
    }
}
