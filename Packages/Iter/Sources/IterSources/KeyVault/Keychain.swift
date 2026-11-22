import Foundation
import Security
import Synchronization

/// A Security-framework failure, by `OSStatus`. Never carries a key or a value.
public struct KeychainError: Error, Hashable, Sendable, CustomStringConvertible {
    public let status: Int32

    public init(status: Int32) { self.status = status }

    public var description: String {
        let message = SecCopyErrorMessageString(status, nil) as String?
        return "Keychain error \(status)" + (message.map { ": \($0)" } ?? "")
    }
}

/// Generic-password storage, keyed by service and account.
public protocol KeychainStoring: Sendable {
    /// The stored bytes, or nil when there is no such item.
    func read(service: String, account: String) throws -> Data?
    /// Creates or replaces the item.
    func write(_ data: Data, service: String, account: String) throws
    /// Removes the item. Removing a missing item is not an error.
    func delete(service: String, account: String) throws
}

/// The real Keychain: generic passwords, update-then-add, as the old Iter code did. On the Mac this is the file-based
/// login keychain: `kSecUseDataProtectionKeychain` is deliberately not set, because the old items live there.
/// Tests and render copies use `InMemoryKeychain`; nothing in the test suites calls this type.
public struct SystemKeychain: KeychainStoring {
    public init() {}

    private func query(service: String, account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    public func read(service: String, account: String) throws -> Data? {
        var q = query(service: service, account: account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        switch status {
        case errSecSuccess: return result as? Data
        case errSecItemNotFound: return nil
        default: throw KeychainError(status: status)
        }
    }

    public func write(_ data: Data, service: String, account: String) throws {
        let base = query(service: service, account: account)
        let updated = SecItemUpdate(base as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updated == errSecSuccess { return }
        guard updated == errSecItemNotFound else { throw KeychainError(status: updated) }
        var add = base
        add[kSecValueData as String] = data
        let added = SecItemAdd(add as CFDictionary, nil)
        guard added == errSecSuccess else { throw KeychainError(status: added) }
    }

    public func delete(service: String, account: String) throws {
        let status = SecItemDelete(query(service: service, account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }
}

/// A Keychain that lives in memory, for tests and render copies.
public final class InMemoryKeychain: KeychainStoring {
    private struct Key: Hashable { var service: String, account: String }

    private let items = Mutex<[Key: Data]>([:])

    public init() {}

    /// Starts with items, as `(service, account, value)`.
    public init(items seed: [(service: String, account: String, value: Data)]) {
        items.withLock { items in
            for item in seed { items[Key(service: item.service, account: item.account)] = item.value }
        }
    }

    public func read(service: String, account: String) throws -> Data? {
        items.withLock { $0[Key(service: service, account: account)] }
    }

    public func write(_ data: Data, service: String, account: String) throws {
        items.withLock { $0[Key(service: service, account: account)] = data }
    }

    public func delete(service: String, account: String) throws {
        items.withLock { _ = $0.removeValue(forKey: Key(service: service, account: account)) }
    }

    /// How many items are stored (for tests).
    public var count: Int { items.withLock { $0.count } }
}
