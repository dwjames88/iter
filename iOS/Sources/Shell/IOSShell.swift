import Foundation
import Observation
import SwiftUI
import IterFeatures
import IterModel
import IterStore

// OWNER: W1 (shell). This is the CONTRACT every other iOS worker codes against. W1 may add members and implement the
// bodies; it must not rename or remove the members marked CONTRACT without the lead's say-so.

/// The iPhone tabs, inside the one floating sheet. CONTRACT.
enum PhoneTab: String, Hashable, CaseIterable, Sendable {
    case find, trips, saved, go
}

/// What a tab's NavigationStack can push. CONTRACT.
enum PhoneRoute: Hashable, Sendable {
    case trip(UUID)
    case tripFolder(UUID)
    case placeFolder(UUID)
    /// A saved place's page.
    case place(UUID)
}

/// The phone sheet's heights. CONTRACT (values W1's to tune).
enum PhoneSheet {
    static let peek = PresentationDetent.height(200)
    static let half = PresentationDetent.medium
    static let full = PresentationDetent.large
    static var detents: Set<PresentationDetent> { [peek, half, full] }
}

/// Everything the iOS app owns once: the composition root, the long-lived models, and the phone/pad navigation state.
@MainActor @Observable
final class IOSShell {
    // CONTRACT: services and long-lived models
    @ObservationIgnored let container: AppContainer
    @ObservationIgnored let library: LibraryModel
    @ObservationIgnored let settings: SettingsModel
    @ObservationIgnored let navigator: AppNavigator
    @ObservationIgnored let find: FindModel
    @ObservationIgnored let go: GoController
    @ObservationIgnored let sharing: SharingCenter
    /// Builds a Conditions model for a place (the container's; tests may swap it).
    @ObservationIgnored let makeConditions: @MainActor (Place) -> ConditionsModel

    // CONTRACT: phone navigation state
    var tab: PhoneTab = .find
    var detent: PresentationDetent = PhoneSheet.half
    /// The sheet's current height in points (the maps inset their content by it).
    var sheetHeight: CGFloat = 0
    var findPath: [PhoneRoute] = []
    var tripsPath: [PhoneRoute] = []
    var savedPath: [PhoneRoute] = []
    /// Settings shows (a sheet on iPhone, the detail on iPad).
    var showsSettings = false

    init(container: AppContainer, find: FindModel? = nil, makeConditions: (@MainActor (Place) -> ConditionsModel)? = nil) {
        self.container = container
        library = container.libraryModel()
        settings = container.settingsModel()
        navigator = AppNavigator(route: .find)
        self.find = find ?? container.makeFindModel()
        self.makeConditions = makeConditions ?? { container.makeConditionsModel(place: $0) }
        go = GoController(container: container, library: library)
        sharing = SharingCenter(library: library)
    }

    /// CONTRACT: the trip the Trips tab has open (the last `.trip` in `tripsPath`), for the map behind the sheet.
    var openTripID: UUID? {
        for route in tripsPath.reversed() { if case .trip(let id) = route { return id } }
        return nil
    }

    @ObservationIgnored private var builds: [UUID: BuildModel] = [:]

    /// CONTRACT: the one Build model for a trip, shared by the map behind the sheet and the builder in it.
    func buildModel(for tripID: UUID) -> BuildModel {
        if let model = builds[tripID] { return model }
        let model = container.makeBuildModel(tripID: tripID)
        builds = [tripID: model]
        return model
    }

    /// CONTRACT: shows an app route on the right tab (phone) or as the detail (pad). Screens usually go through
    /// `navigator.open(_:)`; the shell observes the navigator and calls this.
    func show(_ route: AppRoute) {
        switch route {
        case .find: tab = .find
        case .allTrips: tab = .trips; tripsPath = []
        case .trip(let id): tab = .trips; tripsPath = [.trip(id)]
        case .tripFolder(let id): tab = .trips; tripsPath = [.tripFolder(id)]
        case .savedPlaces: tab = .saved; savedPath = []
        case .placeFolder(let id): tab = .saved; savedPath = [.placeFolder(id)]
        case .place(let id): tab = .saved; savedPath = [.place(id)]
        }
    }
}
