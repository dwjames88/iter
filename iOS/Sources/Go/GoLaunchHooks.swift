import Foundation

// OWNER: W2 (Go). CONTRACT: the app delegate (W1) calls `install` from `application(_:didFinishLaunchingWithOptions:)`,
// before it returns.

@MainActor
enum GoLaunchHooks {
    /// Registers the background refresh task and installs the notification delegate (foreground banners, action
    /// forwarding). `shell` resolves the app's shell lazily. Never asks for any permission.
    static func install(shell: @escaping @MainActor () -> IOSShell?) {}
}
