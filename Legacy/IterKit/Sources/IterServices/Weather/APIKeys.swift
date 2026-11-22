import Foundation
import Security
import Synchronization
import IterCore

/// Stores one API key per provider. Keys are never logged and never go to UserDefaults.
public protocol APIKeyStore: Sendable {
    func key(for source: ForecastSource) -> String?
    func setKey(_ key: String, for source: ForecastSource) throws
    func removeKey(for source: ForecastSource) throws
}

public struct KeychainError: Error, Hashable, Sendable {
    public var status: OSStatus
    public init(status: OSStatus) { self.status = status }
}

/// The login keychain (file based: `kSecUseDataProtectionKeychain` is deliberately not set, so no keychain
/// entitlement is needed). Generic passwords: service "com.dwjames.iter.weather", account = `ForecastSource.rawValue`.
public struct KeychainAPIKeyStore: APIKeyStore {
    public static let defaultService = "com.dwjames.iter.weather"
    private let service: String

    public init(service: String = KeychainAPIKeyStore.defaultService) {
        self.service = service
    }

    private func query(_ source: ForecastSource) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: source.rawValue]
    }

    public func key(for source: ForecastSource) -> String? {
        var q = query(source)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func setKey(_ key: String, for source: ForecastSource) throws {
        let data = Data(key.utf8)
        let status = SecItemUpdate(query(source) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw KeychainError(status: status) }
        var add = query(source)
        add[kSecValueData as String] = data
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
    }

    public func removeKey(for source: ForecastSource) throws {
        let status = SecItemDelete(query(source) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }
}

/// A store that lives in memory (tests, previews).
public final class InMemoryAPIKeyStore: APIKeyStore {
    private let keys: Mutex<[ForecastSource: String]>

    public init(_ keys: [ForecastSource: String] = [:]) {
        self.keys = Mutex(keys)
    }

    public func key(for source: ForecastSource) -> String? { keys.withLock { $0[source] } }
    public func setKey(_ key: String, for source: ForecastSource) throws { keys.withLock { $0[source] = key } }
    public func removeKey(for source: ForecastSource) throws { keys.withLock { $0[source] = nil } }
}

/// Where a resolved key came from, so Settings can say "From environment".
public enum APIKeyOrigin: String, Codable, Hashable, Sendable {
    case environment
    case launchArgument
    case keychain
}

/// A key and where it came from. Its description never contains the key.
public struct ResolvedAPIKey: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let value: String
    public let origin: APIKeyOrigin
    public var description: String { "API key (\(origin.rawValue))" }
    public var debugDescription: String { description }
}

/// Finds the key for a provider: environment variable, then launch argument, then the store (Keychain).
/// Environment names: `ITER_OPENWEATHER_KEY`, `ITER_WINDY_KEY`. A launch argument is `-ITER_OPENWEATHER_KEY value`,
/// read from the argument domain only (never from persisted defaults).
public struct APIKeyResolver: Sendable {
    public static func variableName(for source: ForecastSource) -> String? {
        switch source {
        case .openWeather: "ITER_OPENWEATHER_KEY"
        case .windy: "ITER_WINDY_KEY"
        case .appleWeather, .sample: nil
        }
    }

    public let store: any APIKeyStore
    private let environment: @Sendable () -> [String: String]
    private let launchArgument: @Sendable (String) -> String?

    public init(store: any APIKeyStore,
                environment: @escaping @Sendable () -> [String: String] = { ProcessInfo.processInfo.environment },
                launchArgument: @escaping @Sendable (String) -> String? = APIKeyResolver.processLaunchArgument) {
        self.store = store
        self.environment = environment
        self.launchArgument = launchArgument
    }

    /// The value of `-NAME value` on this process's command line (UserDefaults' argument domain).
    @Sendable public static func processLaunchArgument(_ name: String) -> String? {
        UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)[name] as? String
    }

    public func resolve(_ source: ForecastSource) -> ResolvedAPIKey? {
        func clean(_ s: String?) -> String? {
            guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
            return t
        }
        guard let name = Self.variableName(for: source) else { return nil }
        if let v = clean(environment()[name]) { return ResolvedAPIKey(value: v, origin: .environment) }
        if let v = clean(launchArgument(name)) { return ResolvedAPIKey(value: v, origin: .launchArgument) }
        if let v = clean(store.key(for: source)) { return ResolvedAPIKey(value: v, origin: .keychain) }
        return nil
    }
}
