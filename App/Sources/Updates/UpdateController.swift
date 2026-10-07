#if os(macOS)  // Mac only: the direct-download build's updater and store location (the iOS app excludes these)
import AppKit
import SwiftUI
import Observation
import OSLog
import IterUpdater

/// Drives in-app updates: the daily background check, the manual check, the update window and the install.
/// One shared instance; the window is an AppKit window the controller owns, so it appears whether or not the
/// app has a main window open.
@MainActor @Observable
final class UpdateController {
    enum Phase: Equatable {
        case idle
        case checking
        case upToDate
        case available(UpdateItem)
        /// `nil` when the server did not say how big the download is.
        case downloading(fraction: Double?)
        case verifying
        case installing
        case relaunching
        case failed(message: String, item: UpdateItem?)
    }

    static let shared = UpdateController()

    static let automaticChecksKey = "IterUpdateAutomaticChecks"
    static let lastCheckKey = "IterUpdateLastCheck"
    static let skippedVersionKey = "IterUpdateSkippedVersion"
    private static let log = Logger(subsystem: "com.dwjames.iter", category: "updates")

    /// Settable for previews and tests; the controller drives it in the app.
    var phase: Phase = .idle
    /// The update being downloaded or installed (its size drives the progress text).
    private(set) var workingItem: UpdateItem?
    /// Why this copy cannot install updates, if it cannot. Refreshed when a check starts and by `refreshBlockers()`.
    private(set) var blockers: [InstallBlocker] = []

    var automaticChecks: Bool {
        didSet { defaults.set(automaticChecks, forKey: Self.automaticChecksKey) }
    }
    private(set) var lastCheck: Date?
    private(set) var skippedVersion: String?
    let channel = "release"

    @ObservationIgnored private let updater: Updater?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let presentsWindow: Bool
    @ObservationIgnored private let startupDelay: Duration
    @ObservationIgnored private let relaunch: @MainActor (URL) throws -> Void
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var launchTask: Task<Void, Never>?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var window: NSWindow?
    @ObservationIgnored private var windowDelegate: WindowDelegate?

    /// The app's controller: configured from the main bundle's Info.plist.
    private convenience init() {
        self.init(updater: UpdaterConfiguration.fromBundle(.main).map { Updater(configuration: $0) }, defaults: .standard)
    }

    /// `presentsWindow: false` and a custom `relaunch` keep tests from showing a window or quitting.
    init(updater: Updater?, defaults: UserDefaults, presentsWindow: Bool = true, startupDelay: Duration = .seconds(5),
         relaunch: @escaping @MainActor (URL) throws -> Void = { url in
             try Relauncher.relaunch(appAt: url)
             NSApp.terminate(nil)
         }) {
        #if DEBUG
        let automaticDefault = false
        #else
        let automaticDefault = true
        #endif
        defaults.register(defaults: [Self.automaticChecksKey: automaticDefault])
        self.updater = updater
        self.defaults = defaults
        self.presentsWindow = presentsWindow
        self.startupDelay = startupDelay
        self.relaunch = relaunch
        automaticChecks = defaults.bool(forKey: Self.automaticChecksKey)
        lastCheck = defaults.object(forKey: Self.lastCheckKey) as? Date
        skippedVersion = defaults.string(forKey: Self.skippedVersionKey)
    }

    // MARK: Facts for the UI

    var feedURL: URL? { updater?.configuration.feedURL }
    var currentVersionText: String { updater?.configuration.currentVersion.description ?? VersionText.currentPlain }
    var isBusy: Bool {
        switch phase {
        case .checking, .downloading, .verifying, .installing, .relaunching: true
        default: false
        }
    }

    func refreshBlockers() { blockers = updater?.installBlockers() ?? [] }

    // MARK: Launch

    /// Called once at launch. Does nothing under tests, in-memory runs and the smoke test.
    func start() {
        guard !started, !AppLaunch.isRunningTests, !AppLaunch.inMemoryStore, !AppLaunch.smokeTest else { return }
        beginLaunchWork()
    }

    /// The launch work without the environment guards, so tests can run it.
    func beginLaunchWork() {
        guard !started else { return }
        started = true
        if let updater { Task.detached(priority: .utility) { updater.cleanUp() } }
        launchTask = Task { [startupDelay] in
            try? await Task.sleep(for: startupDelay)
            guard !Task.isCancelled, self.automaticChecks, self.phase == .idle,
                  CheckSchedule().isDue(lastCheck: self.lastCheck, now: .now) else { return }
            await self.check(interactive: false)
        }
    }

    // MARK: Checking

    /// App menu and Settings: shows the window straight away, then the answer.
    func checkForUpdates() {
        switch phase {
        case .checking, .downloading, .verifying, .installing, .relaunching:
            showWindow(activate: true)
            return
        default: break
        }
        phase = .checking
        showWindow(activate: true)
        task = Task { await check(interactive: true) }
    }

    func check(interactive: Bool) async {
        guard let updater else {
            if interactive { phase = .failed(message: UpdateText.noUpdater, item: nil) }
            return
        }
        refreshBlockers()
        let skipping = interactive ? nil : skippedVersion.flatMap { SemanticVersion($0) }
        do {
            let item = try await updater.checkForUpdate(skipping: skipping)
            guard !Task.isCancelled else { return }
            recordCheck()
            if let item {
                phase = .available(item)
                showWindow(activate: interactive)
            } else if interactive {
                phase = .upToDate
            }
        } catch {
            guard !Task.isCancelled else { return }
            Self.log.error("Update check failed: \(String(describing: error), privacy: .public)")
            if interactive { phase = .failed(message: UpdateText.message(for: error), item: nil) }
        }
    }

    private func recordCheck() {
        let now = Date.now
        lastCheck = now
        defaults.set(now, forKey: Self.lastCheckKey)
    }

    // MARK: Installing

    func install(_ item: UpdateItem) {
        guard let updater, !isBusy else { return }
        refreshBlockers()
        if let blocker = blockers.first {
            phase = .failed(message: UpdateText.message(for: blocker), item: item)
            return
        }
        workingItem = item
        phase = .downloading(fraction: nil)
        showWindow(activate: true)
        let report: @Sendable (Double) -> Void = { [weak self] fraction in
            Task { @MainActor in self?.downloadProgress(fraction) }
        }
        task = Task {
            do {
                let archive = try await updater.downloadAndVerify(item, progress: report)
                try Task.checkCancellation()
                phase = .installing
                let installed = try await updater.install(archive: archive, item: item)
                phase = .relaunching
                try relaunch(installed)
            } catch is CancellationError {
                finishCancelled()
            } catch UpdateError.cancelled {
                finishCancelled()
            } catch {
                Self.log.error("Update failed: \(String(describing: error), privacy: .public)")
                phase = .failed(message: UpdateText.message(for: error), item: item)
                Task.detached(priority: .utility) { updater.cleanUp() }
            }
        }
    }

    private func downloadProgress(_ fraction: Double) {
        guard case .downloading = phase else { return }
        if fraction >= 1 { phase = .verifying } else { phase = .downloading(fraction: fraction < 0 ? nil : fraction) }
    }

    private func finishCancelled() {
        phase = .idle
        workingItem = nil
        closeWindow()
        if let updater { Task.detached(priority: .utility) { updater.cleanUp() } }
    }

    /// Stops a download or check in progress (the Cancel button and closing the window).
    func cancel() {
        task?.cancel()
        task = nil
        switch phase {
        case .checking: phase = .idle
        case .downloading: finishCancelled()
        default: break
        }
    }

    // MARK: Choices

    func skip(_ item: UpdateItem) {
        skippedVersion = item.version.description
        defaults.set(skippedVersion, forKey: Self.skippedVersionKey)
        phase = .idle
        closeWindow()
    }

    func remindLater() {
        phase = .idle
        closeWindow()
    }

    /// Closes the window after an answer the user has read ("OK").
    func dismiss() {
        phase = .idle
        closeWindow()
    }

    func openDownloadPage(for item: UpdateItem?) {
        NSWorkspace.shared.open(item?.notesURL ?? UpdateText.releasesPage)
    }

    // MARK: Window

    /// A window in this state cannot be closed: the app is being replaced.
    fileprivate var canCloseWindow: Bool {
        switch phase {
        case .verifying, .installing, .relaunching: false
        default: true
        }
    }

    fileprivate func windowDidClose() {
        task?.cancel()
        task = nil
        if case .downloading = phase, let updater { Task.detached(priority: .utility) { updater.cleanUp() } }
        workingItem = nil
        phase = .idle
    }

    private func showWindow(activate: Bool) {
        guard presentsWindow else { return }
        let window = self.window ?? makeWindow()
        if activate { NSApp.activate() }
        window.makeKeyAndOrderFront(nil)
        if !activate { window.orderFrontRegardless() }
    }

    private func closeWindow() {
        guard let window, window.isVisible else { return }
        window.close()
    }

    private func makeWindow() -> NSWindow {
        let host = NSHostingController(rootView: UpdateWindowView(controller: self))
        let window = NSWindow(contentViewController: host)
        window.styleMask = [.titled, .closable]
        window.title = String(localized: "Software Update", comment: "Update window title")
        window.isReleasedWhenClosed = false
        window.level = .normal
        window.center()
        let delegate = WindowDelegate(controller: self)
        window.delegate = delegate
        windowDelegate = delegate
        self.window = window
        return window
    }

    @MainActor private final class WindowDelegate: NSObject, NSWindowDelegate {
        private unowned let controller: UpdateController
        init(controller: UpdateController) { self.controller = controller }
        func windowShouldClose(_ sender: NSWindow) -> Bool { controller.canCloseWindow }
        func windowWillClose(_ notification: Notification) { controller.windowDidClose() }
    }
}

#endif
