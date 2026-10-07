import SwiftUI
import IterCore
import IterData
import IterFeatures

/// Menu bar commands. Every main action has a shortcut.
struct AppCommands: Commands {
    let model: AppModel
    @FocusedValue(\.navigation) private var navigation

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(String(localized: "New Trip", comment: "Menu item")) {
                navigation?.newTripRequest += 1
                if case .trip = navigation?.selection {} else { navigation?.selection = .trips }
            }
            .keyboardShortcut("n")
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
        CommandGroup(after: .textEditing) {
            Button(String(localized: "Find Spots", comment: "Menu item")) {
                navigation?.selection = .explore
                navigation?.focusSearchRequest += 1
            }
            .keyboardShortcut("f")
            .disabled(navigation == nil)
        }
        CommandMenu(String(localized: "Go", comment: "Menu title")) {
            Button(String(localized: "Trips", comment: "Menu item")) { navigation?.show(.trips) }
                .keyboardShortcut("1")
            Button(String(localized: "Explore", comment: "Menu item")) { navigation?.show(.explore) }
                .keyboardShortcut("2")
            Button(String(localized: "Saved", comment: "Menu item")) { navigation?.show(.saved) }
                .keyboardShortcut("3")
            Button(String(localized: "Scout", comment: "Menu item")) { navigation?.show(.scout) }
                .keyboardShortcut("4")
        }
        CommandMenu(String(localized: "Light", comment: "Menu title")) {
            Button(String(localized: "Refresh Forecasts", comment: "Menu item")) { model.forecasts.retryFailed() }
                .keyboardShortcut("r")
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
