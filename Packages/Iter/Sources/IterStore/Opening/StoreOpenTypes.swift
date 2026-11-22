import Foundation
import SwiftData

/// Why the store could not be opened. In every case the original store files are untouched (for `openFailed` after a
/// backup, the recovery path ran or failed; the original is still never deleted, moved or overwritten).
public enum StoreOpenError: Error {
    /// The backup before the first V5 open failed. Nothing was opened and the store was not touched.
    case backupFailed(any Error)
    /// The store's metadata could not be read.
    case schemaDetectionFailed(any Error)
    /// The store's schema matches no known version (for example it was written by a newer build). Not touched.
    case unrecognizedSchema
    /// The store could not be opened and there is no backup to recover from (it was already at V5, or the recovered
    /// store named by the manifest failed to open).
    case openFailed(any Error)
    /// The V5 open failed, and so did building the recovered store from the backup.
    case recoveryFailed(open: any Error, recovery: any Error)
}

/// What the app should tell the user after the V5 open failed and the app fell back to a recovered store.
public struct RecoveryInfo: Sendable, Equatable {
    /// The recovered store (the active one).
    public var activeURL: URL
    /// The store that failed to open. Never deleted, moved or overwritten.
    public var originalURL: URL
    /// The backup folder (the `.iter` files the recovered store was built from, and the original store files).
    public var backupFolder: URL
    public var recoveredAt: Date
    /// True once the app has shown the one-time notice (`StoreOpener.markRecoveryNoticeShown`).
    public var noticeShown: Bool
    /// Backup `.iter` files that could not be read and so are not in the recovered store (empty normally).
    public var skippedFiles: [String]

    public var needsNotice: Bool { !noticeShown }
}

/// The result of a successful open.
public struct StoreOpenOutcome: Sendable {
    public var container: ModelContainer
    /// The store actually open: the requested URL, or the recovered store's.
    public var activeURL: URL
    /// The backup folder made by this open, or (after a recovery) the one the recovered store came from.
    public var backupFolder: URL?
    /// Non-nil when the app is running on a recovered store. Show a one-time notice while `needsNotice`.
    public var recovered: RecoveryInfo?

    public init(container: ModelContainer, activeURL: URL, backupFolder: URL?, recovered: RecoveryInfo?) {
        self.container = container
        self.activeURL = activeURL
        self.backupFolder = backupFolder
        self.recovered = recovered
    }
}

/// `store-manifest.json`, next to the store: written when the app fell back to a recovered store. While it is there
/// (and the file it names exists) the opener opens that file and never runs recovery again.
struct RecoveryManifest: Codable, Equatable {
    var activeFileName: String
    var originalFileName: String
    /// Absolute path of the backup folder.
    var backupFolder: String
    var recoveredAt: Date
    var noticeShown: Bool
    var skippedFiles: [String] = []

    static let fileName = "store-manifest.json"

    private enum CodingKeys: String, CodingKey {
        case activeFileName, originalFileName, backupFolder, recoveredAt, noticeShown, skippedFiles
    }

    init(activeFileName: String, originalFileName: String, backupFolder: String, recoveredAt: Date, noticeShown: Bool,
         skippedFiles: [String]) {
        self.activeFileName = activeFileName
        self.originalFileName = originalFileName
        self.backupFolder = backupFolder
        self.recoveredAt = recoveredAt
        self.noticeShown = noticeShown
        self.skippedFiles = skippedFiles
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        activeFileName = try c.decode(String.self, forKey: .activeFileName)
        originalFileName = try c.decode(String.self, forKey: .originalFileName)
        backupFolder = try c.decode(String.self, forKey: .backupFolder)
        recoveredAt = try c.decode(Date.self, forKey: .recoveredAt)
        noticeShown = try c.decodeIfPresent(Bool.self, forKey: .noticeShown) ?? false
        skippedFiles = try c.decodeIfPresent([String].self, forKey: .skippedFiles) ?? []
    }

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

/// `backup.json`, inside a backup folder.
struct BackupManifest: Codable {
    struct Counts: Codable { var trips: Int; var stops: Int; var places: Int; var folders: Int }
    var createdAt: Date
    var schemaVersionFound: String
    var sourceStore: String
    var sourceFiles: [String]
    var counts: Counts
    var tripFiles: [String]
    static let fileName = "backup.json"
}
