import SwiftUI

// OWNER: W4 (settings and sharing). CONTRACT: the shell hosts this inside its own NavigationStack (a sheet on iPhone, the
// detail on iPad). No NavigationStack of its own.
struct IOSSettingsScreen: View {
    let shell: IOSShell
    var body: some View { Text(verbatim: "Settings") }
}
