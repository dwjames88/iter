import CryptoKit
import Foundation

/// Decides whether this copy of the app can replace itself.
enum InstallEnvironment {
    static func blockers(bundleURL: URL, publicKey: String?, environment: [String: String]) -> [InstallBlocker] {
        var result: [InstallBlocker] = []
        if environment["APP_SANDBOX_CONTAINER_ID"] != nil { result.append(.sandboxed) }
        if bundleURL.path.contains("/AppTranslocation/") { result.append(.translocated) }

        let fm = FileManager.default
        var unwritable: [String] = []
        let parent = bundleURL.deletingLastPathComponent().path
        if !fm.isWritableFile(atPath: parent) { unwritable.append(parent) }
        if !fm.isWritableFile(atPath: bundleURL.path) { unwritable.append(bundleURL.path) }
        if (try? bundleURL.resourceValues(forKeys: [.volumeIsReadOnlyKey]))?.volumeIsReadOnly == true {
            unwritable.append(bundleURL.path)
        }
        var seen = Set<String>()
        for path in unwritable where seen.insert(path).inserted { result.append(.notWritable(path: path)) }

        if !isValidPublicKey(publicKey) { result.append(.missingPublicKey) }
        return result
    }

    static func isValidPublicKey(_ key: String?) -> Bool {
        guard let key, let raw = Data(base64Encoded: key.trimmingCharacters(in: .whitespacesAndNewlines)),
              raw.count == 32 else { return false }
        return (try? Curve25519.Signing.PublicKey(rawRepresentation: raw)) != nil
    }
}
