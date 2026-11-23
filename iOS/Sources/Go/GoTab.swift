import SwiftUI

// OWNER: W2 (Go). CONTRACT: the shell mounts these for the Go tab.

/// The map behind the sheet while the Go tab is selected.
struct GoTabMap: View {
    let shell: IOSShell
    var body: some View { Color.clear }
}

/// The Go tab's root inside the sheet (the shell wraps it in a NavigationStack).
struct GoTabRoot: View {
    let shell: IOSShell
    var body: some View { Text(verbatim: "Go") }
}
