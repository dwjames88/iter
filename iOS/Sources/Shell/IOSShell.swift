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
    /// The screen's top safe area (status bar, Dynamic Island), kept clear by the maps' controls and framing.
    var mapTopInset: CGFloat = 0
    var findPath: [PhoneRoute] = []
    var tripsPath: [PhoneRoute] = []
    var savedPath: [PhoneRoute] = []
    /// Settings shows (a sheet on iPhone, the detail on iPad).
    var showsSettings = false
    /// The one-time "rebuilt from a backup" notice while it is showing.
    var recovery: RecoveryInfo?
    @ObservationIgnored private var recoveryTaken = false

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
        showsSettings = false
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

    /// The recovery notice, once: shows it while the store says it still needs showing.
    func presentRecoveryNoticeIfNeeded() {
        guard !recoveryTaken, let info = container.store.recovered, info.needsNotice else { return }
        recoveryTaken = true
        recovery = info
    }

    func dismissRecoveryNotice() {
        guard recovery != nil else { return }
        recovery = nil
        container.markRecoveryNoticeShown()
    }

    // MARK: Launch switches

    /// Applies the simulator and render switches (`-IterSection`, `-IterTab`, `-IterSheetDetent`, `-IterOpenPlace`).
    /// Order: section first, then an explicit tab and place, so a render can say both.
    func apply(_ switches: IOSLaunchSwitches) {
        let firstTrip = library.trips.first { $0.name == SampleLibrary.tripName }?.id ?? library.trips.first?.id
        if let route = IOSLaunchSwitches.route(forSection: switches.section, firstTripID: firstTrip) {
            navigator.route = route
            show(route)
        }
        if let tab = switches.tab { self.tab = tab }
        if let detent = switches.detent { self.detent = detent }
        if switches.openFirstPlace, let place = library.savedPlaces.first {
            tab = .saved
            savedPath = [.place(place.id)]
        }
        if let query = switches.findQuery, !query.isEmpty {
            tab = .find
            find.text = query
            find.submit()
        }
        if switches.selectFirstSaved, let place = library.savedPlaces.first.flatMap({ library.place(id: $0.id) }) {
            tab = .find
            find.selectPlace(place)
        }
        if let pane = switches.settingsPane {
            settingsLaunchPane = pane
            showsSettings = true
        }
    }

    /// The Settings pane a launch switch asked for (`-IterSettings root|sources`); Settings reads it once.
    var settingsLaunchPane: String?

    // MARK: Links and files

    /// What `onOpenURL` did with a link.
    enum OpenURLOutcome: Equatable { case sharing, go, unhandled }

    /// The order links are tried in: a `.iter` file belongs to Sharing first, then `iter://go...` belongs to Go.
    static func dispatch(_ url: URL, sharing: (URL) -> Bool, go: (URL) -> Bool) -> OpenURLOutcome {
        if sharing(url) { return .sharing }
        if go(url) { return .go }
        return .unhandled
    }

    /// `onOpenURL`: Sharing, then Go (which also selects the Go tab / the Go row on iPad).
    @discardableResult
    func open(_ url: URL) -> OpenURLOutcome {
        let outcome = Self.dispatch(url, sharing: { sharing.open($0) }, go: { go.handle(url: $0) })
        if outcome == .go { showsSettings = false; tab = .go }
        return outcome
    }

    // MARK: iPad sidebar selection

    /// What the iPad sidebar selects.
    enum PadSelection: Hashable { case app(AppRoute), go, settings }

    var padSelection: PadSelection {
        get {
            if showsSettings { return .settings }
            if tab == .go { return .go }
            return .app(navigator.route ?? .find)
        }
        set {
            switch newValue {
            case .app(let route): showsSettings = false; navigator.open(route); show(route)
            case .go: showsSettings = false; tab = .go
            case .settings: showsSettings = true
            }
        }
    }
}

/// The shell's own launch switches, parsed from the process arguments like `LaunchOptions`.
struct IOSLaunchSwitches: Equatable {
    var section: String?
    var tab: PhoneTab?
    var detent: PresentationDetent?
    var openFirstPlace = false
    /// `-IterFindQuery <text>`: runs a Find search at launch (screenshots of results and discovery).
    var findQuery: String?
    /// `-IterFindSelect saved`: shows the first saved place on Find's card.
    var selectFirstSaved = false
    /// `-IterSettings root|sources`: opens Settings (and a pane).
    var settingsPane: String?
    /// DEBUG only: render the alternative sheet layout for the D6 decision.
    var d6Probe = false

    init(section: String? = nil, tab: PhoneTab? = nil, detent: PresentationDetent? = nil, openFirstPlace: Bool = false, d6Probe: Bool = false) {
        self.section = section; self.tab = tab; self.detent = detent; self.openFirstPlace = openFirstPlace; self.d6Probe = d6Probe
    }

    init(arguments: [String]) {
        func value(_ key: String) -> String? {
            guard let i = arguments.firstIndex(of: key), i + 1 < arguments.count else { return nil }
            return arguments[i + 1].lowercased()
        }
        section = value("-IterSection")
        tab = value("-IterTab").flatMap(PhoneTab.init(rawValue:))
        detent = switch value("-IterSheetDetent") {
        case "peek": PhoneSheet.peek
        case "half": PhoneSheet.half
        case "full": PhoneSheet.full
        default: nil
        }
        openFirstPlace = value("-IterOpenPlace") == "first"
        findQuery = arguments.firstIndex(of: "-IterFindQuery").flatMap { $0 + 1 < arguments.count ? arguments[$0 + 1] : nil }
        selectFirstSaved = value("-IterFindSelect") == "saved"
        settingsPane = value("-IterSettings")
        #if DEBUG
        d6Probe = ["yes", "true", "1"].contains(value("-IterD6Probe") ?? "")
        #endif
    }

    static var current: IOSLaunchSwitches { IOSLaunchSwitches(arguments: ProcessInfo.processInfo.arguments) }

    /// The route for `-IterSection find|trips|places|trip` (the Mac's `AppRoute.forSection`).
    static func route(forSection section: String?, firstTripID: UUID?) -> AppRoute? {
        switch section?.lowercased() {
        case "find": .find
        case "trips": .allTrips
        case "places": .savedPlaces
        case "trip": firstTripID.map { .trip($0) } ?? .allTrips
        default: nil
        }
    }
}

/// Phone or pad shell: an iPad in a compact width (Slide Over, a narrow split) uses the phone shell.
enum ShellLayout: Equatable {
    case phone, pad

    static func resolve(isPad: Bool, horizontalSizeClass: UserInterfaceSizeClass?) -> ShellLayout {
        isPad && horizontalSizeClass == .regular ? .pad : .phone
    }
}
