import AppKit
import SwiftUI
import IterUI

/// What the window says when the library would not open: plain words, the backup folder, and a way out. No crash.
struct StoreFailureView: View {
    let failure: StoreFailure

    var body: some View {
        VStack(alignment: .leading, spacing: IterSpace.lg) {
            HStack(alignment: .top, spacing: IterSpace.md) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(IterColor.warning)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: IterSpace.sm) {
                    Text("Iter Couldn't Open Your Library").font(IterFont.titleSection)
                    Text(failure.message)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    LabeledContent("Backup Folder") {
                        Text(failure.backupFolder.path(percentEncoded: false)).textSelection(.enabled)
                    }
                    .font(IterFont.secondary)
                }
            }
            HStack {
                Spacer(minLength: 0)
                Button("Show Backups in Finder") { NSWorkspace.shared.activateFileViewerSelecting([failure.backupFolder]) }
                Button("Quit Iter") { NSApp.terminate(nil) }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(IterSpace.sheet)
        .frame(minWidth: 520, maxWidth: 640)
        .fixedSize(horizontal: false, vertical: true)
    }
}
