import Foundation

/// Why an update step could not complete. The app localises user-facing text itself; `debugDescription`
/// is plain English for logs.
public enum InstallBlocker: Hashable, Sendable, CustomDebugStringConvertible {
    /// APP_SANDBOX_CONTAINER_ID is in the environment: a sandboxed app cannot replace itself.
    case sandboxed
    /// Gatekeeper path randomisation: the app was launched from a quarantined download, so the real bundle is read-only.
    case translocated
    /// The bundle, its parent folder or its volume cannot be written.
    case notWritable(path: String)
    /// No usable IterUpdatePublicKey, so nothing could be verified.
    case missingPublicKey

    public var debugDescription: String {
        switch self {
        case .sandboxed: "The app is sandboxed and cannot replace itself."
        case .translocated: "The app is running from a translocated (quarantined) location; move it to Applications first."
        case .notWritable(let path): "Cannot write to \(path)."
        case .missingPublicKey: "No valid update public key is configured."
        }
    }
}

public enum UpdateError: Error, Hashable, Sendable, CustomDebugStringConvertible {
    case feedUnavailable(String)
    case feedInvalid(String)
    case noUpdateURL
    case sizeMismatch(expected: Int64, actual: Int64)
    case hashMismatch
    case signatureInvalid
    case archiveInvalid(String)
    case bundleMismatch(String)
    case codeSignatureInvalid(String)
    case blocked(InstallBlocker)
    case installFailed(String)
    case cancelled

    public var debugDescription: String {
        switch self {
        case .feedUnavailable(let reason): "The update server could not be reached: \(reason)"
        case .feedInvalid(let reason): "The update feed is invalid: \(reason)"
        case .noUpdateURL: "The update has no download URL."
        case .sizeMismatch(let expected, let actual): "The download is \(actual) bytes but the feed says \(expected)."
        case .hashMismatch: "The download's SHA-256 does not match the feed."
        case .signatureInvalid: "The download's Ed25519 signature is invalid."
        case .archiveInvalid(let reason): "The update archive is invalid: \(reason)"
        case .bundleMismatch(let reason): "The update does not match the feed: \(reason)"
        case .codeSignatureInvalid(let reason): "The update's code signature is invalid: \(reason)"
        case .blocked(let blocker): "Installing is blocked. \(blocker.debugDescription)"
        case .installFailed(let reason): "The update could not be installed: \(reason)"
        case .cancelled: "The update was cancelled."
        }
    }
}
