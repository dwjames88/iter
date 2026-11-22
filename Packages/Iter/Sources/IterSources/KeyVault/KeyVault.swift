import Foundation
import IterModel

/// Where the old Iter stored its keys, and the `SourceID`s they move to. The ids live here and only here; the sources
/// catalogue may rename them later.
public enum LegacyKeyMapping {
    public static let openWeather: SourceID = "openweather"
    public static let windy: SourceID = "windy"
    public static let googleCSEKey: SourceID = "google.cse"
    public static let googleCSEEngine: SourceID = "google.cse.engine"

    public struct Item: Hashable, Sendable {
        public let legacyService: String
        public let legacyAccount: String
        public let source: SourceID
    }

    public static let weatherService = "com.dwjames.iter.weather"
    public static let discoveryService = "com.dwjames.iter.discovery"

    public static let items: [Item] = [
        Item(legacyService: weatherService, legacyAccount: "openWeather", source: openWeather),
        Item(legacyService: weatherService, legacyAccount: "windy", source: windy),
        Item(legacyService: discoveryService, legacyAccount: "googleAPIKey", source: googleCSEKey),
        Item(legacyService: discoveryService, legacyAccount: "googleEngineID", source: googleCSEEngine),
    ]
}

/// What `KeyVault.migrateLegacyItems()` did. It names sources and outcomes, never values.
public struct KeyVaultMigrationReport: Sendable, Hashable {
    public enum Outcome: Sendable, Hashable {
        /// Copied to the new service.
        case copied
        /// The new service already had a value; left alone.
        case skippedAlreadyPresent
        /// No old item, or it was empty or whitespace.
        case absent
        /// A read or write failed (the Security status text, never a key).
        case failed(String)
    }

    public struct Entry: Sendable, Hashable {
        public var source: SourceID
        public var outcome: Outcome
    }

    /// True when the marker was already set, so nothing was read.
    public var alreadyMigrated: Bool
    public var entries: [Entry]
    /// True when the marker is set after this run (so the old items will not be read again).
    public var markerSet: Bool

    public var copied: [SourceID] { sources(where: { $0 == .copied }) }
    public var skipped: [SourceID] { sources(where: { $0 == .skippedAlreadyPresent }) }
    public var absent: [SourceID] { sources(where: { $0 == .absent }) }
    public var failed: [SourceID] {
        sources(where: { if case .failed = $0 { true } else { false } })
    }

    private func sources(where match: (Outcome) -> Bool) -> [SourceID] {
        entries.filter { match($0.outcome) }.map(\.source)
    }
}

/// The key store: API keys in the Keychain under `com.dwjames.iter.keys`, account = `SourceID`. A key never goes to a
/// log, to UserDefaults, or into any `description`.
public struct KeyVault: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public static let service = "com.dwjames.iter.keys"
    /// The account of the item that records the legacy migration as done.
    public static let migrationMarkerAccount = "_legacyMigrated"

    private let keychain: any KeychainStoring

    public init(keychain: any KeychainStoring) { self.keychain = keychain }

    /// The real Keychain.
    public static func system() -> KeyVault { KeyVault(keychain: SystemKeychain()) }

    public var description: String { "KeyVault(service: \(Self.service))" }
    public var debugDescription: String { description }

    /// The stored key, or nil when none (an empty value counts as none).
    public func key(for source: SourceID) -> String? {
        guard let data = try? keychain.read(service: Self.service, account: source.rawValue),
              let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return nil }
        return text
    }

    /// Stores `key` (trimmed). An empty key removes the item.
    public func setKey(_ key: String, for source: SourceID) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try removeKey(for: source)
        } else {
            try keychain.write(Data(trimmed.utf8), service: Self.service, account: source.rawValue)
        }
    }

    public func removeKey(for source: SourceID) throws {
        try keychain.delete(service: Self.service, account: source.rawValue)
    }

    /// Copies the old Iter Keychain items to the new service, once. Never overwrites an existing new item, never
    /// modifies or deletes an old one. The marker is set only when nothing failed, so a failure retries next time.
    public func migrateLegacyItems() -> KeyVaultMigrationReport {
        if (try? keychain.read(service: Self.service, account: Self.migrationMarkerAccount)) != nil {
            return KeyVaultMigrationReport(alreadyMigrated: true, entries: [], markerSet: true)
        }
        var entries: [KeyVaultMigrationReport.Entry] = []
        for item in LegacyKeyMapping.items {
            entries.append(.init(source: item.source, outcome: migrate(item)))
        }
        var markerSet = false
        if !entries.contains(where: { if case .failed = $0.outcome { true } else { false } }) {
            markerSet = (try? keychain.write(Data("1".utf8), service: Self.service, account: Self.migrationMarkerAccount)) != nil
        }
        return KeyVaultMigrationReport(alreadyMigrated: false, entries: entries, markerSet: markerSet)
    }

    private func migrate(_ item: LegacyKeyMapping.Item) -> KeyVaultMigrationReport.Outcome {
        do {
            if try keychain.read(service: Self.service, account: item.source.rawValue) != nil { return .skippedAlreadyPresent }
            guard let data = try keychain.read(service: item.legacyService, account: item.legacyAccount),
                  let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else { return .absent }
            try keychain.write(Data(text.utf8), service: Self.service, account: item.source.rawValue)
            return .copied
        } catch {
            return .failed(String(describing: error))
        }
    }
}
