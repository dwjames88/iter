import Darwin
import Foundation
import IterUpdater

// Headless stand-in for Iter.app in the end-to-end update test. No NSApplication, no windows.
// Each step is appended to the log named by Info.plist `FixtureLogPath`.

let logPath = Bundle.main.object(forInfoDictionaryKey: "FixtureLogPath") as? String

func log(_ line: String) {
    guard let logPath else { return }
    if !FileManager.default.fileExists(atPath: logPath) {
        FileManager.default.createFile(atPath: logPath, contents: nil)
    }
    guard let handle = FileHandle(forWritingAtPath: logPath) else { return }
    defer { try? handle.close() }
    _ = try? handle.seekToEnd()
    try? handle.write(contentsOf: Data((line + "\n").utf8))
}

func isQuarantined(_ url: URL) -> Bool {
    getxattr(url.path, "com.apple.quarantine", nil, 0, 0, XATTR_NOFOLLOW) >= 0
}

func finish(_ code: Int32) -> Never { exit(code) }

guard let configuration = UpdaterConfiguration.fromBundle(.main) else {
    log("error the bundle has no usable update configuration")
    finish(1)
}
log("launched \(configuration.currentVersion.version) (\(configuration.currentVersion.build)) pid=\(getpid()) quarantined=\(isQuarantined(configuration.bundleURL))")

let updater = Updater(configuration: configuration)
do {
    guard let item = try await updater.checkForUpdate() else {
        log("up-to-date \(configuration.currentVersion.version)")
        finish(0)
    }
    log("found \(item.version) (\(item.build))")
    let archive = try await updater.downloadAndVerify(item) { _ in }
    let size = (try? FileManager.default.attributesOfItem(atPath: archive.path)[.size] as? NSNumber)??.int64Value ?? 0
    log("downloaded \(size)")
    log("verified")
    let installed = try await updater.install(archive: archive, item: item)
    log("installed \(installed.path)")
    updater.cleanUp()
    try Relauncher.relaunch(appAt: installed, hidden: true)
    log("relaunching")
    finish(0)
} catch {
    log("error \(String(reflecting: error))")
    finish(1)
}
