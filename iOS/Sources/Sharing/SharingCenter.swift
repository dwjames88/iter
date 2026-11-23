import Foundation
import Observation
import SwiftUI
import IterFeatures

// OWNER: W4 (settings and sharing). CONTRACT members are used by the shell (W1) and the screens (W3).

/// Getting trips on and off the phone: opening `.iter` files (Files, AirDrop, share sheet, the importer), the
/// merge-or-copy choice, and the outcome notice.
@MainActor @Observable
final class SharingCenter {
    init(library: LibraryModel) {}

    /// CONTRACT: opens a file URL handed to the app (onOpenURL). True when it was an `.iter` file (the shell ignores it then).
    func open(_ url: URL) -> Bool { false }

    /// CONTRACT: shows the file importer.
    func beginImport() {}
}

extension View {
    /// CONTRACT: attaches the importer, the "Merge / Import as Copy" choice and the result alert. The shell applies it once
    /// at the root.
    func sharingFlows(_ center: SharingCenter) -> some View { self }
}

/// CONTRACT: shares one trip as an `.iter` v2 file (AirDrop first in the share sheet).
struct ShareTripButton: View {
    let tripID: UUID
    let library: LibraryModel
    var body: some View { EmptyView() }
}

/// CONTRACT: shares the whole library as an `.iter` v2 file.
struct ShareLibraryButton: View {
    let library: LibraryModel
    var body: some View { EmptyView() }
}
