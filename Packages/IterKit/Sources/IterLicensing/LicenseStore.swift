import Foundation
import CryptoKit
import Security

/// What is kept on disk about an activation.
public struct StoredLicense: Sendable, Equatable, Codable {
    public var key: String
    public var instanceID: String
    public var instanceName: String
    public var lastValidated: Date
    public var email: String?
    public var activatedAt: Date
    /// HMAC over key, instance and last validation date. See `LicenseStore`.
    public var token: String

    public init(key: String, instanceID: String, instanceName: String, lastValidated: Date, email: String?, activatedAt: Date, token: String = "") {
        self.key = key
        self.instanceID = instanceID
        self.instanceName = instanceName
        self.lastValidated = lastValidated
        self.email = email
        self.activatedAt = activatedAt
        self.token = token
    }
}

/// Raw persistence. Implementations hold opaque bytes; `LicenseStore` owns the format.
public protocol LicenseStorage: Sendable {
    func loadRecord() throws -> Data?
    func saveRecord(_ data: Data) throws
    func clearRecord() throws
    /// Per-install random secret, created on first use and kept across `clearRecord()`.
    func salt() throws -> Data
    func loadTrialStart() throws -> Date?
    func saveTrialStart(_ date: Date) throws
}

public struct LicenseStore: Sendable {
    public struct Loaded: Sendable, Equatable {
        public var license: StoredLicense
        /// False when the stored token does not match, i.e. the record was edited.
        public var tokenIsValid: Bool
    }

    private let storage: any LicenseStorage

    public init(storage: any LicenseStorage) { self.storage = storage }

    /// Saves `license`, replacing its token with a fresh one.
    public func save(_ license: StoredLicense) throws {
        var signed = license
        signed.token = try token(for: license)
        try storage.saveRecord(JSONEncoder().encode(signed))
    }

    public func load() throws -> Loaded? {
        guard let data = try storage.loadRecord() else { return nil }
        guard let license = try? JSONDecoder().decode(StoredLicense.self, from: data) else {
            // Unreadable record: treat as tampered rather than silently dropping the activation.
            return nil
        }
        let expected = try Data(base64Encoded: license.token).map { stored in
            try mac(for: license).isValid(stored)
        } ?? false
        return Loaded(license: license, tokenIsValid: expected)
    }

    public func clear() throws { try storage.clearRecord() }
    public func trialStart() throws -> Date? { try storage.loadTrialStart() }
    public func saveTrialStart(_ date: Date) throws { try storage.saveTrialStart(date) }

    private struct Mac {
        let key: SymmetricKey
        let message: Data
        func isValid(_ code: Data) -> Bool { HMAC<SHA256>.isValidAuthenticationCode(code, authenticating: message, using: key) }
    }

    private func mac(for l: StoredLicense) throws -> Mac {
        let message = "\(l.key)|\(l.instanceID)|\(l.lastValidated.timeIntervalSince1970)"
        return Mac(key: SymmetricKey(data: try storage.salt()), message: Data(message.utf8))
    }

    private func token(for l: StoredLicense) throws -> String {
        let m = try mac(for: l)
        return Data(HMAC<SHA256>.authenticationCode(for: m.message, using: m.key)).base64EncodedString()
    }
}

// MARK: Implementations

/// In-memory storage for tests and previews.
public final class InMemoryLicenseStorage: LicenseStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var record: Data?
    private var saltData: Data?
    private var trial: Date?

    public init() {}

    public func loadRecord() throws -> Data? { lock.withLock { record } }
    public func saveRecord(_ data: Data) throws { lock.withLock { record = data } }
    public func clearRecord() throws { lock.withLock { record = nil } }
    public func salt() throws -> Data {
        lock.withLock {
            if let saltData { return saltData }
            let new = Data((0..<32).map { _ in UInt8.random(in: .min ... .max) })
            saltData = new
            return new
        }
    }
    public func loadTrialStart() throws -> Date? { lock.withLock { trial } }
    public func saveTrialStart(_ date: Date) throws { lock.withLock { trial = date } }
}

public struct KeychainError: Error, Sendable, Equatable { public let status: OSStatus }

/// Generic-password Keychain items under `service` (default `com.dwjames.iter.license`), one per account:
/// `license`, `salt`, `trial-start`.
public struct KeychainLicenseStorage: LicenseStorage {
    public let service: String

    public init(service: String = "com.dwjames.iter.license") { self.service = service }

    public func loadRecord() throws -> Data? { try read("license") }
    public func saveRecord(_ data: Data) throws { try write("license", data) }
    public func clearRecord() throws { try delete("license") }

    public func salt() throws -> Data {
        if let existing = try read("salt") { return existing }
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else { throw KeychainError(status: status) }
        let data = Data(bytes)
        try write("salt", data)
        return data
    }

    public func loadTrialStart() throws -> Date? {
        guard let data = try read("trial-start"), let s = String(data: data, encoding: .utf8), let t = TimeInterval(s) else { return nil }
        return Date(timeIntervalSince1970: t)
    }

    public func saveTrialStart(_ date: Date) throws {
        try write("trial-start", Data(String(date.timeIntervalSince1970).utf8))
    }

    private func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    private func read(_ account: String) throws -> Data? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
        return out as? Data
    }

    private func write(_ account: String, _ data: Data) throws {
        let update = SecItemUpdate(query(account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw KeychainError(status: update) }
        var q = query(account)
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let add = SecItemAdd(q as CFDictionary, nil)
        guard add == errSecSuccess else { throw KeychainError(status: add) }
    }

    private func delete(_ account: String) throws {
        let status = SecItemDelete(query(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }
}
