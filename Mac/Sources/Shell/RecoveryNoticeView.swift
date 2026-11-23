import SwiftUI
import IterUI

/// The one-time notice after Iter rebuilt the library from a backup. "Show in Finder" runs only on the user's click.
struct RecoveryNoticeView: View {
    let backupFolder: URL
    var skippedFiles: [String] = []
    var showInFinder: () -> Void
    var dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: IterSpace.lg) {
            HStack(alignment: .top, spacing: IterSpace.md) {
                Image(systemName: "externaldrive.badge.checkmark")
                    .font(.system(size: 32))
                    .foregroundStyle(IterColor.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: IterSpace.sm) {
                    Text("Iter Rebuilt Your Library From a Backup").font(IterFont.titleSection)
                    Text("Iter couldn't open your library the way it was saved, so it made a new one from the latest backup. Your original files were left exactly as they were, and the backup is still on this Mac.")
                        .fixedSize(horizontal: false, vertical: true)
                    LabeledContent("Backup Folder") {
                        Text(backupFolder.path(percentEncoded: false))
                            .textSelection(.enabled)
                            .multilineTextAlignment(.trailing)
                    }
                    .font(IterFont.secondary)
                    if !skippedFiles.isEmpty {
                        Text("These backup files couldn't be read, so they aren't in the new library: \(skippedFiles.joined(separator: ", ")).")
                            .font(IterFont.secondary)
                            .foregroundStyle(IterColor.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            HStack {
                Spacer(minLength: 0)
                Button("Show in Finder", action: showInFinder)
                Button("OK", action: dismiss).keyboardShortcut(.defaultAction)
            }
        }
        .padding(IterSpace.sheet)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }
}
