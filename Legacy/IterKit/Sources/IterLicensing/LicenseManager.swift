import Foundation

/// Owns the licence lifecycle: activate, validate, deactivate and the offline grace rules. UI-agnostic; the UI
/// layer calls `currentState()` and republishes.
public actor LicenseManager {
    public static let defaultGracePeriod: TimeInterval = 14 * 86_400
    public static let defaultTrialDays = 14

    private let client: LicenseClient
    private let store: LicenseStore
    private let clock: @Sendable () -> Date
    private let gracePeriod: TimeInterval
    private let maxClockSkew: TimeInterval
    private let trialDays: Int
    /// Set when a validation proves the key is dead; there is no stored record left to say so.
    private var terminal: LicenseState?

    public init(
        client: LicenseClient,
        store: LicenseStore,
        gracePeriod: TimeInterval = LicenseManager.defaultGracePeriod,
        maxClockSkew: TimeInterval = 86_400,
        trialDays: Int = LicenseManager.defaultTrialDays,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.client = client
        self.store = store
        self.gracePeriod = gracePeriod
        self.maxClockSkew = maxClockSkew
        self.trialDays = trialDays
        self.clock = clock
    }

    /// Starts the trial clock if it has not started yet. Safe to call on every launch.
    public func startTrialIfNeeded() throws {
        if try store.trialStart() == nil { try store.saveTrialStart(clock()) }
    }

    @discardableResult
    public func activate(key rawKey: String, instanceName: String) async throws -> LicenseState {
        guard let key = LicenseKey(parsing: rawKey) else { throw LicenseError.malformedKey }
        let response = try await client.activate(key: key, instanceName: instanceName)
        guard let instance = response.instance else { throw LicenseError.decoding }
        let now = clock()
        try store.save(StoredLicense(
            key: key.value,
            instanceID: instance.id,
            instanceName: instance.name,
            lastValidated: now,
            email: response.meta?.customerEmail,
            activatedAt: instance.createdAt ?? now
        ))
        terminal = nil
        return try currentState(now: now)
    }

    /// Asks the server whether the stored key is still good. Network trouble is not an error: the state falls back to
    /// the grace rules. A dead key clears the activation and yields `.revoked` (or `.expired` for a lapsed licence).
    @discardableResult
    public func validate() async throws -> LicenseState {
        guard let loaded = try store.load(), let key = LicenseKey(parsing: loaded.license.key) else {
            return try currentState()
        }
        do {
            let response = try await client.validate(key: key, instanceID: loaded.license.instanceID)
            var license = loaded.license
            let now = clock()
            license.lastValidated = now
            if let email = response.meta?.customerEmail { license.email = email }
            try store.save(license)
            terminal = nil
            return try currentState(now: now)
        } catch let error as LicenseError {
            switch error {
            case .invalidKey, .keyDisabled, .productMismatch:
                try store.clear()
                terminal = .revoked
            case .keyExpired:
                try store.clear()
                terminal = .expired
            case .network, .rateLimited, .server, .decoding, .badRequest, .activationLimitReached, .malformedKey:
                break
            }
            return try currentState()
        }
    }

    /// Frees this Mac's seat and forgets the key. Throws on network trouble so the user can retry, keeping the key.
    public func deactivate() async throws {
        guard let loaded = try store.load(), let key = LicenseKey(parsing: loaded.license.key) else { return }
        do {
            _ = try await client.deactivate(key: key, instanceID: loaded.license.instanceID)
        } catch LicenseError.invalidKey, LicenseError.keyDisabled, LicenseError.keyExpired {
            // Already gone on the server; clear locally.
        }
        try store.clear()
        terminal = nil
    }

    public func currentState(now: Date? = nil) throws -> LicenseState {
        let now = now ?? clock()
        if let loaded = try store.load() {
            guard loaded.tokenIsValid else { return .expired }
            let elapsed = now.timeIntervalSince(loaded.license.lastValidated)
            if elapsed < -maxClockSkew || elapsed > gracePeriod { return .expired }
            return .licensed(email: loaded.license.email, activatedAt: loaded.license.activatedAt)
        }
        if let terminal { return terminal }
        if let start = try store.trialStart() {
            return .trial(startedAt: start, now: now, lengthDays: trialDays, maxClockSkew: maxClockSkew)
        }
        return .unlicensed
    }
}
