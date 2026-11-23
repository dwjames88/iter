import Foundation

/// Writes an exported `.iter` v2 file to a temporary folder so the Mac can hand it to AirDrop ("Send to iPhone"). The
/// Mac's commands and the package tests both go through this, so the tests prove what the menu sends.
public enum SendFile {
    /// Writes `file` as `<temp>/<unique folder>/<suggested name>` (the file keeps its readable name for the receiver).
    public static func write(_ file: ExportedLibrary, in directory: URL = FileManager.default.temporaryDirectory) throws -> URL {
        let folder = directory.appending(path: "IterSend-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: file.suggestedFileName, directoryHint: .notDirectory)
        try file.data.write(to: url, options: .atomic)
        return url
    }

    /// The one trip as a ready-to-send file, or nil when the trip is gone.
    @MainActor
    public static func trip(_ id: UUID, from library: LibraryModel) throws -> URL? {
        guard let file = try library.exportTrip(id) else { return nil }
        return try write(file)
    }

    /// The whole library as a ready-to-send file.
    @MainActor
    public static func library(_ library: LibraryModel) throws -> URL { try write(try library.exportLibrary()) }
}
