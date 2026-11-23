import Foundation
import Observation
import IterFeatures
import IterModel
import IterScreens

// OWNER: W2 (Go). CONTRACT members are used by the shell (W1); keep their names and signatures.

/// Owns trip mode for the app: the one `GoModel` on the live engine (or fakes in tests, render copies and sample runs), the
/// trips Go offers, starting and restoring runs, deep links and notification actions.
@MainActor @Observable
final class GoController {
    init(container: AppContainer, library: LibraryModel) {}

    /// CONTRACT: a run is going (the shell shows the Go tab first while true).
    var isRunning: Bool { false }

    /// CONTRACT: the trips Go offers to start, from the library.
    var trips: [GoTripChoice] { [] }

    /// CONTRACT: starts trip mode for a trip (from Build's "Start Trip" or Go's own picker).
    func start(tripID: UUID, stopID: UUID? = nil, alreadyThere: Bool = false) async {}

    /// CONTRACT: at launch, resumes an unfinished run if the library has one. True when it did.
    func restoreAtLaunch() async -> Bool { false }

    /// CONTRACT: the scene became active (foreground + permissions refresh).
    func sceneBecameActive() async {}

    /// CONTRACT: handles `iter://go...` links. True when the URL was Go's (the shell then shows the Go tab).
    func handle(url: URL) -> Bool { false }
}
