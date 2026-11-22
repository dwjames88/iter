#if canImport(ActivityKit) && os(iOS)
import ActivityKit
import Foundation

/// The Live Activity's static part. Shared by the iOS app (which starts it) and the widget extension (which draws it).
public struct GoActivityAttributes: ActivityAttributes {
    public typealias ContentState = GoActivityContent

    public var tripID: UUID
    public var tripName: String

    public init(tripID: UUID, tripName: String) {
        self.tripID = tripID
        self.tripName = tripName
    }
}
#endif
