import Foundation
import Testing
import IterModel
import IterStore
@testable import IterFeatures

/// The IterStore fixtures, read by path from this file (no resource bundle needed).
enum Fixtures {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()   // IterFeaturesTests -> Tests
        .appending(path: "IterStoreTests/Fixtures", directoryHint: .isDirectory)

    static func scratch(_ label: String = "iter-lib") throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(label)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

/// A fixed clock the models read; steps one second per call so `updatedAt` order is deterministic.
final class TickingClock: @unchecked Sendable {
    private let lock = NSLock()
    private var t: TimeInterval
    init(_ start: Date = AppContainer.testNow) { t = start.timeIntervalSince1970 }
    func callAsFunction() -> Date { lock.lock(); defer { lock.unlock() }; t += 1; return Date(timeIntervalSince1970: t) }
}

@MainActor
struct LibraryFixture {
    let container: AppContainer
    let undo = UndoManager()
    let model: LibraryModel
    var library: LibraryStore { container.library }

    /// A sample container's in-memory library with a window undo manager attached.
    init(seed: Bool = false) throws {
        container = try AppContainer.test(seed: seed)
        model = container.libraryModel(timeZone: TimeZone(identifier: "America/Denver")!)
        undo.groupsByEvent = false
        container.library.undoManager = undo
    }

    /// One undo step, the way the Edit menu runs it.
    func undoStep() { undo.undo() }
    func redoStep() { undo.redo() }
    func settle() async { for _ in 0..<4 { await Task.yield() } }
}
