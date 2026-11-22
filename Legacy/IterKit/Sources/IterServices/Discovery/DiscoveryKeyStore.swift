import Foundation
import Security
import Synchronization

/// The user's own Google Programmable Search credentials. Stored in the Keychain, never in the repo,
/// UserDefaults or logs.
public protocol DiscoveryKeyStore: Sendable {
    var googleAPIKey: String? { get }
    var googleEngineID: String? { get }
    func setGoogleAPIKey(_ key: String) throws
    func setGoogleEngineID(_ id: String) throws
    func removeGoogleCredentials() throws
}

extension DiscoveryKeyStore {
    /// Both halves are stored and non-empty.
    public var hasGoogleCredentials: Bool {
        !(googleAPIKey ?? "").trimmingCharacters(in: .whitespaces).isEmpty && !(googleEngineID ?? "").trimmingCharacters(in: .whitespaces).isEmpty
    }
}

/// The login keychain, as `KeychainAPIKeyStore` does it: generic passwords, no data-protection keychain entitlement.
/// Service "com.dwjames.iter.discovery" (distinct from the weather keys); accounts "googleAPIKey" and "googleEngineID".
public struct KeychainDiscoveryKeyStore: DiscoveryKeyStore {
    public static let defaultService = "com.dwjames.iter.discovery"
    private let service: String

    public init(service: String = KeychainDiscoveryKeyStore.defaultService) { self.service = service }

    public var googleAPIKey: String? { read("googleAPIKey") }
    public var googleEngineID: String? { read("googleEngineID") }
    public func setGoogleAPIKey(_ key: String) throws { try write(key, account: "googleAPIKey") }
    public func setGoogleEngineID(_ id: String) throws { try write(id, account: "googleEngineID") }
    public func removeGoogleCredentials() throws {
        try remove("googleAPIKey")
        try remove("googleEngineID")
    }

    private func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    private func read(_ account: String) -> String? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func write(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        let status = SecItemUpdate(query(account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw KeychainError(status: status) }
        var add = query(account)
        add[kSecValueData as String] = data
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
    }

    private func remove(_ account: String) throws {
        let status = SecItemDelete(query(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }
}

/// A store that lives in memory (tests, previews).
public final class InMemoryDiscoveryKeyStore: DiscoveryKeyStore {
    private let values: Mutex<(key: String?, engine: String?)>

    public init(googleAPIKey: String? = nil, googleEngineID: String? = nil) {
        values = Mutex((googleAPIKey, googleEngineID))
    }

    public var googleAPIKey: String? { values.withLock { $0.key } }
    public var googleEngineID: String? { values.withLock { $0.engine } }
    public func setGoogleAPIKey(_ key: String) throws { values.withLock { $0.key = key } }
    public func setGoogleEngineID(_ id: String) throws { values.withLock { $0.engine = id } }
    public func removeGoogleCredentials() throws { values.withLock { $0 = (nil, nil) } }
}
