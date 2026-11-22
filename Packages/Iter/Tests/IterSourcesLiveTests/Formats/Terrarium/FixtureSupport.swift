import Foundation

/// Locates files under the test bundle's copied `Fixtures` folder.
enum Fixtures {
    static var root: URL {
        Bundle.module.resourceURL!.appendingPathComponent("Fixtures", isDirectory: true)
    }

    static func url(_ relativePath: String) -> URL { root.appendingPathComponent(relativePath) }

    static func data(_ relativePath: String) throws -> Data { try Data(contentsOf: url(relativePath)) }
}
