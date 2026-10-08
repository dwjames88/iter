import Foundation

/// Features that sit behind a licence once enforcement is on. Placeholders until the paid line is drawn.
public enum ProFeature: String, Sendable, CaseIterable {
    case unlimitedTrips
    case advancedExport
}

public struct LicenseGate: Sendable, Equatable {
    /// Info.plist key fed by the `ITER_LICENSING_ENFORCED` build setting.
    public static let infoPlistKey = "IterLicensingEnforced"

    public let isEnforced: Bool

    public init(isEnforced: Bool) { self.isEnforced = isEnforced }

    /// Reads `IterLicensingEnforced` from the main bundle. Missing or unrecognised values mean not enforced.
    public static let current = LicenseGate(isEnforced: parseEnforced(Bundle.main.object(forInfoDictionaryKey: infoPlistKey)))

    /// Accepts a Bool, or a string such as "YES", "true", "1". An unexpanded "$(ITER_LICENSING_ENFORCED)" is false.
    public static func parseEnforced(_ raw: Any?) -> Bool {
        switch raw {
        case let b as Bool: return b
        case let s as String: return ["yes", "true", "1"].contains(s.trimmingCharacters(in: .whitespaces).lowercased())
        default: return false
        }
    }

    public func allows(_ feature: ProFeature, state: LicenseState) -> Bool {
        guard isEnforced else { return true }
        switch state {
        case .licensed, .trial: return true
        case .unlicensed, .expired, .revoked: return false
        }
    }
}
