import AppKit
import SwiftUI

@main
struct IterApp: App {
    private let launch: LaunchResult

    init() {
        // Hosted tests (xcodebuild test, scripts/test-mac.sh): never show, activate or take focus. Hook for the test host
        // only; keep it first.
        if IterApp.isUnderTest { NSApplication.shared.setActivationPolicy(.prohibited) }
        launch = LaunchResult.launch()
        if case .ready(let shell) = launch {
            SmokeRun.watchdog(shell)
            shell.updates.start()
        }
    }

    static var isUnderTest: Bool { ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil }

    private var shell: AppShell? {
        if case .ready(let shell) = launch { shell } else { nil }
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            switch launch {
            case .ready(let shell): MainWindow(shell: shell)
            case .failed(let failure): StoreFailureView(failure: failure)
            }
        }
        .defaultSize(width: 1280, height: 820)
        // Under the test runner the host app opens no window, so tests never take over the screen.
        .defaultLaunchBehavior(IterApp.isUnderTest ? .suppressed : .automatic)
        .commands {
            ShellCommands(shell: shell)
            UpdateCommands()
            #if DEBUG
            DebugCommands(shell: shell)
            #endif
        }

        Settings {
            switch launch {
            case .ready(let shell): SettingsView(shell: shell)
            case .failed(let failure): StoreFailureView(failure: failure).frame(width: 520)
            }
        }
    }
}
