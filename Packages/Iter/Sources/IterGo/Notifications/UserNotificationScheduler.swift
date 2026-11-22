#if canImport(UserNotifications)
import Foundation
import UserNotifications

/// The real adapter over `UNUserNotificationCenter`. Never created in tests. Interruption level is `.active` (no time-sensitive
/// entitlement on a free Personal Team). Future requests use time-interval triggers (absolute instants, so a time-zone change
/// on the road does not move them); immediates have no trigger. The app shell must set a `UNUserNotificationCenterDelegate`
/// to show banners while the app is in the foreground and to handle the Navigate and Not yet actions.
public final class UserNotificationScheduler: NotificationScheduling, @unchecked Sendable {
    public init() {}

    private var center: UNUserNotificationCenter { UNUserNotificationCenter.current() }

    public func add(_ request: GoNotificationRequest) async throws {
        let content = UNMutableNotificationContent()
        content.title = request.title
        content.body = request.body
        content.sound = .default
        content.categoryIdentifier = request.categoryID
        content.threadIdentifier = request.threadID
        content.userInfo = request.userInfo
        content.interruptionLevel = .active
        let trigger: UNNotificationTrigger? = request.fireAt.map {
            UNTimeIntervalNotificationTrigger(timeInterval: max(1, $0.timeIntervalSinceNow), repeats: false)
        }
        try await center.add(UNNotificationRequest(identifier: request.id, content: content, trigger: trigger))
    }

    public func removePending(ids: [String]) async {
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    public func removeAllPending() async { center.removeAllPendingNotificationRequests() }

    public func pendingIDs() async -> [String] {
        await center.pendingNotificationRequests().map(\.identifier)
    }

    public func authorization() async -> NotificationAuthorization {
        switch await center.notificationSettings().authorizationStatus {
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .provisional: .provisional
        default: .authorized
        }
    }

    public func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    public func registerCategories() async {
        let navigate = UNNotificationAction(identifier: GoNotificationCategory.navigateAction, title: "Navigate", options: [.foreground])
        let notYet = UNNotificationAction(identifier: GoNotificationCategory.notYetAction, title: "Not yet", options: [])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: GoNotificationCategory.navigate, actions: [navigate], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: GoNotificationCategory.arrival, actions: [notYet], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: GoNotificationCategory.info, actions: [], intentIdentifiers: [], options: []),
        ])
    }
}
#endif
