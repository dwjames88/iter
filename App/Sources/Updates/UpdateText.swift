#if os(macOS)  // Mac only: the direct-download build's updater and store location (the iOS app excludes these)
import Foundation
import IterUpdater

/// Every user-facing sentence of the updater. The package gives errors, this gives them words.
enum UpdateText {
    static let releasesPage = URL(string: "https://github.com/dwjames88/iter/releases/latest")!

    static func message(for blocker: InstallBlocker) -> String {
        switch blocker {
        case .sandboxed:
            String(localized: "This copy of Iter runs in the App Sandbox, so it can't replace itself. Download the new version from GitHub instead.",
                   comment: "Update blocked: the app is sandboxed")
        case .translocated:
            String(localized: "macOS is running Iter from a temporary location because it was opened from Downloads. Move Iter to your Applications folder, open it again, then check for updates.",
                   comment: "Update blocked: Gatekeeper path randomisation")
        case .notWritable(let path):
            String(localized: "Iter can't write to “\(folder(of: path))”. Move Iter to your Applications folder, or download the update from GitHub.",
                   comment: "Update blocked: the folder holding Iter is read-only; the placeholder is a folder name")
        case .missingPublicKey:
            String(localized: "This build of Iter has no update signing key, so it can't verify updates. Install a release build from GitHub.",
                   comment: "Update blocked: no public key in this build")
        }
    }

    static func message(for error: UpdateError) -> String {
        switch error {
        case .feedUnavailable:
            String(localized: "Iter couldn't reach the update server. Check your connection and try again.", comment: "Update failure")
        case .feedInvalid:
            String(localized: "The update server sent something Iter couldn't read. Try again later.", comment: "Update failure")
        case .noUpdateURL:
            String(localized: "This update has no download link. Try again later, or download it from GitHub.", comment: "Update failure")
        case .sizeMismatch, .hashMismatch:
            String(localized: "The download was damaged, so it wasn't installed. Try again.", comment: "Update failure: size or checksum mismatch")
        case .signatureInvalid:
            String(localized: "The download isn't signed by Iter's release key, so it wasn't installed.", comment: "Update failure: bad signature")
        case .archiveInvalid:
            String(localized: "The downloaded update couldn't be opened, so it wasn't installed.", comment: "Update failure: bad zip")
        case .bundleMismatch:
            String(localized: "The download isn't the version the update server announced, so it wasn't installed.", comment: "Update failure: wrong app or version inside the zip")
        case .codeSignatureInvalid:
            String(localized: "The new version's code signature isn't valid, so it wasn't installed.", comment: "Update failure: bad code signature")
        case .blocked(let blocker):
            message(for: blocker)
        case .installFailed:
            String(localized: "Iter couldn't install the update. Your current version is unchanged.", comment: "Update failure: replacing the app failed")
        case .cancelled:
            String(localized: "The update was cancelled.", comment: "Update failure: cancelled")
        }
    }

    /// Any error, including ones that are not `UpdateError`.
    static func message(for error: Error) -> String {
        if let error = error as? UpdateError { return message(for: error) }
        return String(localized: "Iter couldn't check for updates. Try again later.", comment: "Update failure: unexpected error")
    }

    static let noUpdater = String(localized: "This build of Iter has no update feed, so it can't check for updates.", comment: "Update failure: no feed URL")

    private static func folder(of path: String) -> String {
        let url = URL(filePath: path)
        // A path to the bundle names its folder; a folder path names itself.
        return url.pathExtension == "app" ? url.deletingLastPathComponent().lastPathComponent : url.lastPathComponent
    }
}

#endif
