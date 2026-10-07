import Darwin
import Foundation
@testable import IterUpdater

/// A throwaway directory that restores permissions before deleting, so a chmod 0555 test cannot leak.
final class TempDir: @unchecked Sendable {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("IterUpdaterTests-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func child(_ name: String) -> URL { url.appendingPathComponent(name) }

    deinit { remove() }

    func remove() {
        let fm = FileManager.default
        chmod(url.path, 0o755)
        for sub in (try? fm.subpathsOfDirectory(atPath: url.path)) ?? [] {
            chmod(url.appendingPathComponent(sub).path, 0o755)
        }
        try? fm.removeItem(at: url)
    }
}

func runTool(_ path: String, _ arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    struct ToolFailed: Error { let path: String; let status: Int32 }
    guard process.terminationStatus == 0 else { throw ToolFailed(path: path, status: process.terminationStatus) }
}

@discardableResult
func makeBundle(
    in directory: URL, name: String = "Iter.app", identifier: String = "studio.test.iter",
    version: String, build: Int, executable: URL? = nil, extraFile: String? = nil
) throws -> URL {
    let fm = FileManager.default
    let app = directory.appendingPathComponent(name, isDirectory: true)
    let macOS = app.appendingPathComponent("Contents/MacOS", isDirectory: true)
    try fm.createDirectory(at: macOS, withIntermediateDirectories: true)
    let plist: [String: Any] = [
        "CFBundleIdentifier": identifier, "CFBundleExecutable": "Iter", "CFBundleName": "Iter",
        "CFBundlePackageType": "APPL", "CFBundleShortVersionString": version, "CFBundleVersion": String(build),
    ]
    try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        .write(to: app.appendingPathComponent("Contents/Info.plist"))
    let exe = macOS.appendingPathComponent("Iter")
    if let executable {
        try fm.copyItem(at: executable, to: exe)
    } else {
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: exe)
    }
    chmod(exe.path, 0o755)
    if let extraFile {
        let resources = app.appendingPathComponent("Contents/Resources", isDirectory: true)
        try fm.createDirectory(at: resources, withIntermediateDirectories: true)
        try Data("data".utf8).write(to: resources.appendingPathComponent(extraFile))
    }
    return app
}

func zip(_ source: URL, to archive: URL, keepParent: Bool = true) throws {
    try runTool("/usr/bin/ditto", ["-c", "-k"] + (keepParent ? ["--keepParent"] : []) + [source.path, archive.path])
}

func hasQuarantine(_ url: URL) -> Bool {
    getxattr(url.path, "com.apple.quarantine", nil, 0, 0, XATTR_NOFOLLOW) >= 0
}

func anyQuarantine(in root: URL) -> Bool {
    if hasQuarantine(root) { return true }
    return ((try? FileManager.default.subpathsOfDirectory(atPath: root.path)) ?? [])
        .contains { hasQuarantine(root.appendingPathComponent($0)) }
}

/// Builds an item that matches `archive`, signed with `privateKey`.
func makeItem(
    for archive: URL, version: String, build: Int, privateKey: String,
    url: URL = URL(string: "https://example.test/Iter.zip")!
) throws -> UpdateItem {
    let size = (try FileManager.default.attributesOfItem(atPath: archive.path)[.size] as? NSNumber)?.int64Value ?? 0
    return UpdateItem(
        version: SemanticVersion(version)!, build: build, url: url, length: size,
        sha256: try UpdateVerifier.sha256Hex(ofFileAt: archive),
        edSignature: try UpdateSigning.sign(fileAt: archive, privateKey: privateKey),
        publishedAt: Date(timeIntervalSince1970: 1_790_000_000))
}

func makeUpdater(
    bundle: URL, publicKey: String?, identifier: String = "studio.test.iter", current: String = "0.1.0",
    requireSignature: Bool = false, workDirectory: URL, feedURL: URL = URL(string: "https://feed.test/appcast.json")!,
    session: URLSession = .shared
) -> Updater {
    Updater(
        configuration: UpdaterConfiguration(
            feedURL: feedURL, publicKey: publicKey, bundleURL: bundle, bundleIdentifier: identifier,
            currentVersion: AppVersion(version: SemanticVersion(current)!, build: 1),
            workDirectory: workDirectory, requireValidCodeSignature: requireSignature),
        session: session)
}
