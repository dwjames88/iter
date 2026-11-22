import Foundation
import Synchronization
import Testing
import IterModel
@testable import IterSources

/// Fails writes on demand; every other call goes to an in-memory keychain. Never touches the real Keychain.
private final class FlakyKeychain: KeychainStoring {
    let base: InMemoryKeychain
    let failWrites = Mutex(false)
    init(base: InMemoryKeychain) { self.base = base }
    func read(service: String, account: String) throws -> Data? { try base.read(service: service, account: account) }
    func write(_ data: Data, service: String, account: String) throws {
        if failWrites.withLock({ $0 }) { throw KeychainError(status: -25308) }
        try base.write(data, service: service, account: account)
    }
    func delete(service: String, account: String) throws { try base.delete(service: service, account: account) }
}

private func legacy(_ values: [String: String]) -> InMemoryKeychain {
    let kc = InMemoryKeychain()
    for item in LegacyKeyMapping.items {
        if let v = values[item.legacyAccount] {
            try! kc.write(Data(v.utf8), service: item.legacyService, account: item.legacyAccount)
        }
    }
    return kc
}

private func text(_ kc: any KeychainStoring, _ service: String, _ account: String) -> String? {
    (try? kc.read(service: service, account: account)).flatMap { $0 }.flatMap { String(data: $0, encoding: .utf8) }
}

@Suite("KeyVault")
struct KeyVaultTests {
    @Test func setReadRemove() throws {
        let vault = KeyVault(keychain: InMemoryKeychain())
        #expect(vault.key(for: "windy") == nil)
        try vault.setKey("  abc123 \n", for: "windy")
        #expect(vault.key(for: "windy") == "abc123")
        try vault.setKey("", for: "windy")
        #expect(vault.key(for: "windy") == nil)
        try vault.setKey("k", for: "windy")
        try vault.removeKey(for: "windy")
        #expect(vault.key(for: "windy") == nil)
    }

    @Test func descriptionNeverHoldsAKey() throws {
        let vault = KeyVault(keychain: InMemoryKeychain())
        try vault.setKey("super-secret-value", for: "windy")
        #expect(!"\(vault)".contains("super-secret"))
        #expect(!String(reflecting: vault).contains("super-secret"))
    }

    @Test func allFourMigrate() {
        let old = legacy(["openWeather": "ow", "windy": "wn", "googleAPIKey": "gk", "googleEngineID": "ge"])
        let report = KeyVault(keychain: old).migrateLegacyItems()
        let vault = KeyVault(keychain: old)
        #expect(report.copied.count == 4)
        #expect(report.markerSet && !report.alreadyMigrated)
        #expect(vault.key(for: LegacyKeyMapping.openWeather) == "ow")
        #expect(vault.key(for: LegacyKeyMapping.windy) == "wn")
        #expect(vault.key(for: LegacyKeyMapping.googleCSEKey) == "gk")
        #expect(vault.key(for: LegacyKeyMapping.googleCSEEngine) == "ge")
    }

    @Test func someMigrate() {
        let old = legacy(["windy": "wn", "googleEngineID": "ge"])
        let report = KeyVault(keychain: old).migrateLegacyItems()
        #expect(report.copied == [LegacyKeyMapping.windy, LegacyKeyMapping.googleCSEEngine])
        #expect(report.absent == [LegacyKeyMapping.openWeather, LegacyKeyMapping.googleCSEKey])
        #expect(report.failed.isEmpty && report.markerSet)
    }

    @Test func markerMeansNothingIsRead() {
        let old = legacy(["windy": "wn"])
        let vault = KeyVault(keychain: old)
        _ = vault.migrateLegacyItems()
        try? vault.removeKey(for: LegacyKeyMapping.windy)
        let again = vault.migrateLegacyItems()
        #expect(again.alreadyMigrated && again.entries.isEmpty)
        #expect(vault.key(for: LegacyKeyMapping.windy) == nil)
    }

    @Test func existingNewKeyIsNotOverwritten() throws {
        let old = legacy(["windy": "old-value", "openWeather": "ow"])
        let vault = KeyVault(keychain: old)
        try vault.setKey("typed-by-user", for: LegacyKeyMapping.windy)
        let report = vault.migrateLegacyItems()
        #expect(report.skipped == [LegacyKeyMapping.windy])
        #expect(report.copied == [LegacyKeyMapping.openWeather])
        #expect(vault.key(for: LegacyKeyMapping.windy) == "typed-by-user")
    }

    @Test func oldItemsAreUntouched() {
        let old = legacy(["openWeather": " ow ", "windy": "wn", "googleAPIKey": "gk", "googleEngineID": "ge"])
        _ = KeyVault(keychain: old).migrateLegacyItems()
        #expect(text(old, LegacyKeyMapping.weatherService, "openWeather") == " ow ")
        #expect(text(old, LegacyKeyMapping.weatherService, "windy") == "wn")
        #expect(text(old, LegacyKeyMapping.discoveryService, "googleAPIKey") == "gk")
        #expect(text(old, LegacyKeyMapping.discoveryService, "googleEngineID") == "ge")
        // Trimmed on the way in.
        #expect(text(old, KeyVault.service, "openweather") == "ow")
    }

    @Test func emptyAndWhitespaceAreSkipped() {
        let old = legacy(["openWeather": "", "windy": "  \n\t", "googleAPIKey": "gk"])
        let report = KeyVault(keychain: old).migrateLegacyItems()
        #expect(report.copied == [LegacyKeyMapping.googleCSEKey])
        #expect(report.absent.count == 3)
        #expect(text(old, KeyVault.service, "openweather") == nil)
        #expect(text(old, KeyVault.service, "windy") == nil)
    }

    @Test func failedWriteLeavesMarkerUnsetAndNextRunCompletes() {
        let base = legacy(["openWeather": "sekret-ow-9", "windy": "sekret-wn-9"])
        let flaky = FlakyKeychain(base: base)
        flaky.failWrites.withLock { $0 = true }
        let vault = KeyVault(keychain: flaky)
        let first = vault.migrateLegacyItems()
        #expect(first.failed.count == 2)
        #expect(!first.markerSet)
        #expect(text(base, KeyVault.service, KeyVault.migrationMarkerAccount) == nil)
        for case .failed(let message) in first.entries.map(\.outcome) { #expect(!message.contains("sekret")) }

        flaky.failWrites.withLock { $0 = false }
        let second = vault.migrateLegacyItems()
        #expect(second.copied.count == 2 && second.failed.isEmpty && second.markerSet)
        #expect(vault.key(for: LegacyKeyMapping.openWeather) == "sekret-ow-9")
        // And a third run reads nothing.
        #expect(vault.migrateLegacyItems().alreadyMigrated)
    }

    @Test func migrationIsIdempotentWithoutMarker() {
        let old = legacy(["windy": "wn"])
        let vault = KeyVault(keychain: old)
        _ = vault.migrateLegacyItems()
        try? old.delete(service: KeyVault.service, account: KeyVault.migrationMarkerAccount)
        let report = vault.migrateLegacyItems()
        #expect(report.skipped == [LegacyKeyMapping.windy])
        #expect(vault.key(for: LegacyKeyMapping.windy) == "wn")
    }
}
