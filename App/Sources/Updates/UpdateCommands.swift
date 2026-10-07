#if os(macOS)  // Mac only: the direct-download build's updater and store location (the iOS app excludes these)
import AppKit
import SwiftUI

/// The app menu's About and Check for Updates items.
struct UpdateCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button(String(localized: "About Iter", comment: "Menu item")) {
                NSApp.orderFrontStandardAboutPanel(options: [.version: VersionText.aboutPanelBuild])
            }
            Button(String(localized: "Check for Updates…", comment: "Menu item")) {
                UpdateController.shared.checkForUpdates()
            }
        }
    }
}

#endif
