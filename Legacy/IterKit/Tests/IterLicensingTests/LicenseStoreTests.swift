import Testing
import Foundation
import Security
@testable import IterLicensing

@Suite("LicenseStore")
struct LicenseStoreTests {
    let sample = StoredLicense(
        key: "K", instanceID: "I", instanceName: "N", lastValidated: Date(timeIntervalSince1970: 1_000),
        email: "a@b.c", activatedAt: Date(timeIntervalSince1970: 500))

    @Test func inMemoryRoundTripVerifiesToken() throws {
        let store = LicenseStore(storage: InMemoryLicenseStorage())
        #expect(try store.load() == nil)
        try store.save(sample)
        let loaded = try #require(try store.load())
        #expect(loaded.tokenIsValid)
        #expect(loaded.license.instanceID == "I")
        try store.clear()
        #expect(try store.load() == nil)
    }

    @Test func tokenDependsOnSaltSoCopiedRecordsFail() throws {
        let a = InMemoryLicenseStorage(), b = InMemoryLicenseStorage()
        try LicenseStore(storage: a).save(sample)
        try b.saveRecord(try #require(try a.loadRecord()))
        #expect(try LicenseStore(storage: b).load()?.tokenIsValid == false)
    }

    @Test func keychainRoundTrip() throws {
        let storage = KeychainLicenseStorage(service: "com.dwjames.iter.license.tests.\(UUID().uuidString)")
        let store = LicenseStore(storage: storage)
        do {
            try store.save(sample)
        } catch let error as KeychainError {
            try Test.cancel("Keychain unavailable in this environment (OSStatus \(error.status)); round trip not exercised.")
        }
        defer { try? store.clear(); try? storage.deleteAllForTesting() }
        let loaded = try #require(try store.load())
        #expect(loaded.tokenIsValid)
        #expect(loaded.license.email == "a@b.c")
        try store.saveTrialStart(Date(timeIntervalSince1970: 42))
        #expect(try store.trialStart() == Date(timeIntervalSince1970: 42))
        try store.clear()
        #expect(try store.load() == nil)
    }
}

extension KeychainLicenseStorage {
    func deleteAllForTesting() throws {
        for account in ["license", "salt", "trial-start"] {
            let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
            SecItemDelete(q as CFDictionary)
        }
    }
}
