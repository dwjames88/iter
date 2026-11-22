import Foundation
@testable import IterStore

struct InjectedFailure: Error, Equatable { var label: String }

/// Real file operations that fail on demand, to prove a failed backup leaves nothing behind.
final class FlakyFileOperations: StoreFileOperations, @unchecked Sendable {
    enum Operation: String { case copy, move, write, remove }
    private let real = DefaultStoreFileOperations()
    private let lock = NSLock()
    private var counts: [Operation: Int] = [:]
    /// Fails the n-th (1-based) call of `operation` and every later one.
    let failFrom: [Operation: Int]

    init(failFrom: [Operation: Int]) { self.failFrom = failFrom }

    private func tick(_ operation: Operation) throws {
        lock.lock()
        counts[operation, default: 0] += 1
        let n = counts[operation]!
        lock.unlock()
        if let limit = failFrom[operation], n >= limit { throw InjectedFailure(label: "\(operation.rawValue)#\(n)") }
    }

    func fileExists(at url: URL) -> Bool { real.fileExists(at: url) }
    func createDirectory(at url: URL) throws { try real.createDirectory(at: url) }
    func copyItem(at source: URL, to destination: URL) throws { try tick(.copy); try real.copyItem(at: source, to: destination) }
    func moveItem(at source: URL, to destination: URL) throws { try tick(.move); try real.moveItem(at: source, to: destination) }
    func removeItem(at url: URL) throws { try tick(.remove); try real.removeItem(at: url) }
    func contentsOfDirectory(at url: URL) throws -> [URL] { try real.contentsOfDirectory(at: url) }
    func write(_ data: Data, to url: URL) throws { try tick(.write); try real.write(data, to: url) }
    func read(_ url: URL) throws -> Data { try real.read(url) }
    func fileSize(at url: URL) throws -> Int { try real.fileSize(at: url) }
}

extension StoreContainerFactory {
    /// The live factory, except the V5 open of exactly `url` fails.
    static func failingCurrent(for url: URL) -> StoreContainerFactory {
        StoreContainerFactory(
            openCurrent: { requested in
                if requested.standardizedFileURL == url.standardizedFileURL { throw InjectedFailure(label: "v5 open") }
                return try StoreContainerFactory.live.openCurrent(requested)
            },
            openLegacyV4: StoreContainerFactory.live.openLegacyV4)
    }

    /// The live factory, except the scratch (frozen V4) open fails.
    static var failingScratch: StoreContainerFactory {
        StoreContainerFactory(openCurrent: StoreContainerFactory.live.openCurrent,
                              openLegacyV4: { _ in throw InjectedFailure(label: "scratch open") })
    }
}
