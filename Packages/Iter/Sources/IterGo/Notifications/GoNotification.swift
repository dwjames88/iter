import Foundation
import IterPlan

/// The kinds of notification trip mode raises.
public enum GoNotificationKind: String, Codable, Hashable, Sendable, CaseIterable {
    case leaveSoon, leaveNow, late, missed, stayCheck, conditionsChanged, arrival

    /// "<stopID>-<kind>". For leaveSoon and leaveNow this equals `AlarmPlan.id(for:kind:)`.
    public func id(for stopID: UUID) -> String { "\(stopID.uuidString)-\(rawValue)" }

    /// The kind of an id made by `id(for:)`, if it is one.
    public static func kind(ofID id: String) -> GoNotificationKind? {
        allCases.first { id.hasSuffix("-" + $0.rawValue) }
    }
}

/// Category identifiers and action identifiers shared with the app's notification delegate.
public enum GoNotificationCategory {
    /// Leave now and late: a "Navigate" action that opens Apple Maps.
    public static let navigate = "iter.go.navigate"
    /// Automatic arrival: a "Not yet" action that undoes it (D12).
    public static let arrival = "iter.go.arrival"
    /// Everything else: no actions.
    public static let info = "iter.go.info"

    public static let navigateAction = "iter.go.action.navigate"
    public static let notYetAction = "iter.go.action.notYet"
}

/// One notification, as data. `fireAt == nil` means deliver now.
public struct GoNotificationRequest: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var kind: GoNotificationKind
    public var stopID: UUID
    public var tripID: UUID
    public var fireAt: Date?
    public var title: String
    public var body: String
    public var categoryID: String
    /// The trip id: notifications group by trip.
    public var threadID: String
    public var userInfo: [String: String]

    public init(id: String, kind: GoNotificationKind, stopID: UUID, tripID: UUID, fireAt: Date?, title: String, body: String,
                categoryID: String, threadID: String, userInfo: [String: String] = [:]) {
        self.id = id
        self.kind = kind
        self.stopID = stopID
        self.tripID = tripID
        self.fireAt = fireAt
        self.title = title
        self.body = body
        self.categoryID = categoryID
        self.threadID = threadID
        self.userInfo = userInfo
    }

    /// A stable (process-independent) hash of what the user would read: the "text unchanged" test.
    public var contentHash: String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in "\(title)\u{1f}\(body)\u{1f}\(categoryID)".utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(hash, radix: 16)
    }
}

public enum NotificationAuthorization: String, Codable, Hashable, Sendable {
    case notDetermined, denied, authorized, provisional
}
