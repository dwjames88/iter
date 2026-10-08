import Foundation
import Observation

/// The state behind Settings ▸ Licence on every platform. Wraps `LicenseManager` and the Keychain store; the panes
/// only lay it out. It never starts a trial: this build is free, so a Mac with no key reads as unlicensed.
@MainActor @Observable
public final class LicenceSettingsModel {
    public private(set) var state: LicenseState = .unlicensed
    /// The stored key with all but the last four characters hidden. nil when no key is stored.
    public private(set) var maskedKey: String?
    /// The name this Mac was activated under. nil when nothing is stored.
    public private(set) var instanceName: String?
    public private(set) var isBusy = false
    /// A short sentence for the last failed action. Cleared when the next action starts.
    public private(set) var errorMessage: String?

    /// What the person typed or pasted.
    public var keyInput = ""
    /// "This Mac's name": combined with the hardware model to label the activation.
    public var nameInput: String

    private let manager: LicenseManager
    private let store: LicenseStore

    public init(manager: LicenseManager, store: LicenseStore, suggestedName: String = LicenceSettingsModel.accountName()) {
        self.manager = manager
        self.store = store
        self.nameInput = suggestedName
    }

    /// The real thing: Keychain storage under `com.dwjames.iter.license`, Lemon Squeezy over `URLSession.shared`.
    public static func live(suggestedName: String = LicenceSettingsModel.accountName()) -> LicenceSettingsModel {
        let store = LicenseStore(storage: KeychainLicenseStorage())
        let manager = LicenseManager(client: LicenseClient(configuration: LicenceSetup.clientConfiguration), store: store)
        return LicenceSettingsModel(manager: manager, store: store, suggestedName: suggestedName)
    }

    public static func accountName() -> String {
        let full = NSFullUserName()
        return full.isEmpty ? NSUserName() : full
    }

    // MARK: Derived

    /// The typed key, when it is shaped like one.
    public var parsedKey: LicenseKey? { LicenseKey(parsing: keyInput) }
    public var canActivate: Bool { parsedKey != nil && !isBusy }
    public var isLicensed: Bool { if case .licensed = state { true } else { false } }
    public var statusTitle: String { LicenceText.statusTitle(state) }
    public var statusDetail: String? { LicenceText.statusDetail(state) }

    public var email: String? { if case .licensed(let email, _) = state { email } else { nil } }
    public var activatedAt: Date? { if case .licensed(_, let date) = state { date } else { nil } }

    // MARK: Actions

    /// Reads the stored licence and the current state. Call when the pane appears.
    public func refresh() async {
        do {
            state = try await manager.currentState()
            reloadStored()
        } catch {
            errorMessage = LicenceText.message(for: error)
        }
    }

    public func activate() async {
        await perform {
            let name = InstanceName.make(userChosen: self.nameInput)
            self.state = try await self.manager.activate(key: self.keyInput, instanceName: name)
            self.keyInput = ""
        }
    }

    /// Asks the server whether the stored key is still good. Offline is not an error; the grace rules apply.
    public func validate() async {
        await perform { self.state = try await self.manager.validate() }
    }

    /// Frees this Mac's activation and forgets the key.
    public func deactivate() async {
        await perform {
            try await self.manager.deactivate()
            self.state = try await self.manager.currentState()
        }
    }

    private func perform(_ work: @MainActor () async throws -> Void) async {
        guard !isBusy else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do { try await work() } catch { errorMessage = LicenceText.message(for: error) }
        reloadStored()
    }

    private func reloadStored() {
        let license = (try? store.load())?.license
        maskedKey = license.flatMap { LicenseKey(parsing: $0.key)?.masked }
        instanceName = license?.instanceName
    }
}
