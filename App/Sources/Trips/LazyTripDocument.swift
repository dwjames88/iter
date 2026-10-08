import SwiftUI
import IterData

// MARK: - Lazy share

/// Shares a trip as the same `.iter` file as `TripDocument` (same type and file name), but builds the document only when
/// the share is performed, on the main actor, so the toolbar can hold it without exporting the trip on every body pass.
struct LazyTripDocument: Transferable {
    let tripName: String
    let build: @MainActor @Sendable () -> TripDocument?

    struct Unavailable: Error {}

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .iterTrip) { item in
            let document = await MainActor.run { item.build() }
            guard let document else { throw Unavailable() }
            return try document.encoded()
        }
        .suggestedFileName { TripDocument.suggestedFileName(forTripNamed: $0.tripName) }
    }
}
