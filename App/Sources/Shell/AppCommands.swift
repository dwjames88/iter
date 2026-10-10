import SwiftUI
import IterCore
import IterData
import IterFeatures

/// Menu bar commands. Every main action has a shortcut.
struct AppCommands: Commands {
    let model: AppModel
    @FocusedValue(\.navigation) private var navigation
    @FocusedValue(\.editLocation) private var editLocation
    @AppStorage(MapStyleChoice.storageKey) private var mapStyleRaw = MapStyleChoice.default.rawValue
    @AppStorage(DaylightClock.storageKey) private var showsDaylight = true

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(String(localized: "New Trip", comment: "Menu item")) {
                navigation?.newTripRequest += 1
                if case .trip = navigation?.selection {} else { navigation?.selection = .trips }
            }
            .keyboardShortcut("n")
            .disabled(navigation == nil)
            Button(String(localized: "New Folder", comment: "Menu item")) {
                // Asks the current screen to make a folder: Locations when it is up, otherwise All Trips.
                guard let navigation else { return }
                switch navigation.selection {
                case .locations, .locationFolder:
                    navigation.newFolderRequest = .locations
                case .location:
                    navigation.show(.locations)
                    navigation.newFolderRequest = .locations
                case .tripFolder, .trips:
                    navigation.newFolderRequest = .trips
                case .trip, .explore, nil:
                    navigation.show(.trips)
                    navigation.newFolderRequest = .trips
                }
            }
            .keyboardShortcut("n", modifiers: [.command, .option])
            .disabled(navigation == nil)
            Button(String(localized: "Add Spot on Map", comment: "Menu item")) {
                navigation?.selection = .explore
                navigation?.addSpotModeRequest += 1
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .disabled(navigation == nil)
            Divider()
            Button(String(localized: "Import Trip…", comment: "Menu item")) {
                navigation?.importRequest += 1
                if case .trip = navigation?.selection {} else { navigation?.selection = .trips }
            }
            .keyboardShortcut("o")
            .disabled(navigation == nil)
        }
        CommandGroup(after: .pasteboard) {
            Button(String(localized: "Edit Location…", comment: "Menu item: edit the saved or own place shown")) { editLocation?.run() }
                .keyboardShortcut("e")
                .disabled(editLocation == nil)
        }
        CommandGroup(after: .textEditing) {
            Button(String(localized: "Find Spots", comment: "Menu item")) {
                navigation?.selection = .explore
                navigation?.focusSearchRequest += 1
            }
            .keyboardShortcut("f")
            .disabled(navigation == nil)
            Button(String(localized: "Search Here", comment: "Menu item: search the part of the map in view in Explore")) {
                navigation?.selection = .explore
                navigation?.searchHereRequest += 1
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
            .disabled(navigation == nil)
        }
        CommandGroup(after: .toolbar) {
            Menu(String(localized: "Map Style", comment: "Menu title")) {
                Picker(String(localized: "Map Style", comment: "Menu title"), selection: $mapStyleRaw) {
                    ForEach(MapStyleChoice.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.inline)
                Toggle(String(localized: "Show Daylight", comment: "Menu item: shade the night side of the globe when zoomed out"), isOn: $showsDaylight)
            }
        }
        CommandMenu(String(localized: "Go", comment: "Menu title")) {
            Button(String(localized: "Trips", comment: "Menu item")) { navigation?.show(.trips) }
                .keyboardShortcut("1")
            Button(String(localized: "Explore", comment: "Menu item")) { navigation?.show(.explore) }
                .keyboardShortcut("2")
            Button(String(localized: "Locations", comment: "Menu item")) { navigation?.show(.locations) }
                .keyboardShortcut("3")
        }
        CommandMenu(String(localized: "Light", comment: "Menu title")) {
            Button(String(localized: "Refresh Forecasts", comment: "Menu item")) { model.forecasts.retryFailed() }
                .keyboardShortcut("r")
        }
        CommandGroup(replacing: .help) {
            Button(String(localized: "Welcome to Iter", comment: "Help menu item: reopens the first-run guide")) {
                model.onboarding.present(at: .welcome)
            }
        }
        DebugCommands(model: model, navigation: navigation)
    }
}

/// Debug menu: testing aids only. Sample data is off by default and labelled wherever it shows.
struct DebugCommands: Commands {
    let model: AppModel
    let navigation: AppNavigation?
    @AppStorage("IterShowLayoutGrid") private var showLayoutGrid = false

    var body: some Commands {
        CommandMenu(String(localized: "Debug", comment: "Menu title")) {
            Toggle(String(localized: "Use Sample Weather", comment: "Debug menu item"), isOn: Binding(
                get: { model.sampleDataEnabled },
                set: { model.setSampleData($0) }))
            Toggle(String(localized: "Show Layout Grid", comment: "Debug menu item: overlay the 8 pt grid and lane guides"), isOn: $showLayoutGrid)
            Button(String(localized: "Seed Sample Trip", comment: "Debug menu item")) {
                let trip = model.store.seedSampleTrip(startDay: model.today(in: .current).adding(days: 1))
                navigation?.show(.trip(trip.id))
            }
            Divider()
            Button(String(localized: "Reset All Data…", comment: "Debug menu item"), role: .destructive) {
                let alert = NSAlert()
                alert.messageText = String(localized: "Delete all trips and spots?", comment: "Reset alert title")
                alert.informativeText = String(localized: "This can't be undone.", comment: "Reset alert message")
                alert.alertStyle = .critical
                alert.addButton(withTitle: String(localized: "Delete Everything", comment: "Reset alert button"))
                alert.addButton(withTitle: String(localized: "Cancel", comment: "Alert button"))
                if alert.runModal() == .alertFirstButtonReturn {
                    model.store.resetAllData()
                    navigation?.selection = .trips
                }
            }
        }
    }
}
