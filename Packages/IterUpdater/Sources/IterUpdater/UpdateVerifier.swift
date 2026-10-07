import CryptoKit
import Foundation

public enum UpdateVerifier {
    /// SHA-256 as lowercase hex, streamed in 1 MiB chunks so a large archive never sits in memory twice.
    public static func sha256Hex(ofFileAt url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Verifies an Ed25519 signature over the exact bytes of the file.
    /// A malformed signature is `signatureInvalid`; a malformed key is `blocked(.missingPublicKey)`.
    public static func verifySignature(fileAt url: URL, signature: String, publicKey: String) throws {
        guard let keyData = Data(base64Encoded: publicKey.trimmingCharacters(in: .whitespacesAndNewlines)),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData) else {
            throw UpdateError.blocked(.missingPublicKey)
        }
        guard let signatureData = Data(base64Encoded: signature.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw UpdateError.signatureInvalid
        }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard key.isValidSignature(signatureData, for: data) else { throw UpdateError.signatureInvalid }
    }

    /// Cheapest check first: length, then hash, then the signature, which is the root of trust.
    public static func verify(archive: URL, against item: UpdateItem, publicKey: String) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: archive.path)
        let actual = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        guard actual == item.length else { throw UpdateError.sizeMismatch(expected: item.length, actual: actual) }
        guard try sha256Hex(ofFileAt: archive) == item.sha256.lowercased() else { throw UpdateError.hashMismatch }
        try verifySignature(fileAt: archive, signature: item.edSignature, publicKey: publicKey)
    }
}
