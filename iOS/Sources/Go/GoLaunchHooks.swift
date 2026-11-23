import Foundation
import UserNotifications
import IterGo

// OWNER: W2 (Go). CONTRACT: the app delegate (W1) calls `install` from `application(_:didFinishLaunchingWithOptions:)`,
// before it returns.

@MainActor
enum GoLaunchHooks {
    /// What `install` kept alive (the center holds its delegate weakly).
    private static var delegate: GoNotificationDelegate?
    private static var registeredBackground = false

    /// Registers the background refresh task and installs the notification delegate (foreground banners, action
    /// forwarding). `shell` resolves the app's shell lazily. Never asks for any permission.
    static func install(shell: @escaping @MainActor () -> IOSShell?) {
        guard !isTestHost(ProcessInfo.processInfo.environment) else { return }
        registerBackgroundRefresh(shell: shell, permitted: permittedIdentifiers(Bundle.main))
        let delegate = GoNotificationDelegate(shell: shell)
        self.delegate = delegate
        UNUserNotificationCenter.current().delegate = delegate
    }

    /// A unit-test or UI-test host: `BGTaskScheduler` and the notification center are left alone there.
    static func isTestHost(_ environment: [String: String]) -> Bool {
        environment["XCTestConfigurationFilePath"] != nil || environment["XCTestBundlePath"] != nil
            || environment["XCTestSessionIdentifier"] != nil
    }

    static func permittedIdentifiers(_ bundle: Bundle) -> [String] {
        bundle.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String] ?? []
    }

    /// `BGTaskScheduler.register` raises when the identifier is not in the plist, so it is registered only when it is (and once).
    static func registerBackgroundRefresh(shell: @escaping @MainActor () -> IOSShell?, permitted: [String]) {
        guard !registeredBackground, permitted.contains(GoBackground.refreshTaskIdentifier) else { return }
        registeredBackground = true
        BackgroundTaskScheduler.register { completion in
            Task { @MainActor in
                await shell()?.go.model.backgroundRefresh()
                completion(true)
            }
        }
    }
}

/// Shows Go's notifications as banners while the app is open and sends their actions to the Go model. Setting it asks for nothing.
final class GoNotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    private let shell: @MainActor () -> IOSShell?

    init(shell: @escaping @MainActor () -> IOSShell?) { self.shell = shell }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let content = response.notification.request.content
        let action = response.actionIdentifier
        let category = content.categoryIdentifier
        let info = Self.stringInfo(content.userInfo)
        nonisolated(unsafe) let done = completionHandler
        Task { @MainActor in
            await self.handle(actionIdentifier: action, categoryIdentifier: category, userInfo: info)
            done()
        }
    }

    /// The part that matters, callable directly by tests. A Go notification (tapped or acted on) shows the Go tab; the Navigate and
    /// Not yet actions go to the model. A cold launch from a notification restores the run first.
    @MainActor
    func handle(actionIdentifier: String, categoryIdentifier: String, userInfo: [String: String]) async {
        guard categoryIdentifier.hasPrefix("iter.go."), let shell = shell() else { return }
        shell.tab = .go
        _ = await shell.go.restoreAtLaunch()
        guard actionIdentifier != UNNotificationDefaultActionIdentifier, actionIdentifier != UNNotificationDismissActionIdentifier else { return }
        await shell.go.model.handleNotificationAction(identifier: actionIdentifier, userInfo: userInfo)
    }

    /// `userInfo` as the model wants it: string values only.
    static func stringInfo(_ userInfo: [AnyHashable: Any]) -> [String: String] {
        var out: [String: String] = [:]
        for (key, value) in userInfo {
            guard let key = key as? String else { continue }
            if let s = value as? String { out[key] = s } else if let u = value as? UUID { out[key] = u.uuidString }
        }
        return out
    }
}
