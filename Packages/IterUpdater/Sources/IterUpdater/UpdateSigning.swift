import CryptoKit
import Foundation

/// Why a key could not be used. Distinct from `UpdateError` because it only arises in tooling.
public enum SigningKeyError: Error, Hashable, Sendable, CustomDebugStringConvertible {
    case invalidPrivateKey
    case invalidPublicKey

    public var debugDescription: String {
        switch self {
        case .invalidPrivateKey: "The private key is not a base64 32-byte Ed25519 key."
        case .invalidPublicKey: "The public key is not a base64 32-byte Ed25519 key."
        }
    }
}

/// Ed25519 signing for release tooling. Keys and signatures travel as base64 of the raw bytes.
public enum UpdateSigning {
    public static func generateKeyPair() -> (privateKey: String, publicKey: String) {
        let key = Curve25519.Signing.PrivateKey()
        return (key.rawRepresentation.base64EncodedString(), key.publicKey.rawRepresentation.base64EncodedString())
    }

    public static func publicKey(forPrivateKey privateKey: String) throws -> String {
        try signingKey(privateKey).publicKey.rawRepresentation.base64EncodedString()
    }

    public static func sign(fileAt url: URL, privateKey: String) throws -> String {
        // Ed25519 signs the whole message, so the file has to be addressable in full; map rather than copy.
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        return try sign(data: data, privateKey: privateKey)
    }

    public static func sign(data: Data, privateKey: String) throws -> String {
        try signingKey(privateKey).signature(for: data).base64EncodedString()
    }

    private static func signingKey(_ base64: String) throws -> Curve25519.Signing.PrivateKey {
        guard let raw = Data(base64Encoded: base64.trimmingCharacters(in: .whitespacesAndNewlines)),
              let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) else {
            throw SigningKeyError.invalidPrivateKey
        }
        return key
    }
}
