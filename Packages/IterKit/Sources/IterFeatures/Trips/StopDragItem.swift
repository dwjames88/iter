import Foundation
import CoreTransferable
import UniformTypeIdentifiers

/// What a dragged stop row carries: enough to find the stop again, nothing else.
/// The type is private to Iter; dropping a stop anywhere else does nothing.
public struct StopDragItem: Codable, Hashable, Sendable, Transferable {
    public var tripID: UUID
    public var stopID: UUID

    public init(tripID: UUID, stopID: UUID) {
        self.tripID = tripID
        self.stopID = stopID
    }

    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .iterStopDrag)
    }
}

extension UTType {
    /// In-app drag of a trip stop. Not declared in Info.plist on purpose: it never leaves the app.
    public static let iterStopDrag = UTType(exportedAs: "com.dwjames.iter.trip-stop")
}
