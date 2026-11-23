import SwiftUI
import IterStore
import IterUI

/// What the app says when the library would not open: plain words and where the backups are. No crash.
struct IOSStoreFailureView: View {
    let failure: IOSStoreFailure

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: IterSpace.lg) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(IterColor.warning)
                    .accessibilityHidden(true)
                Text("Iter Couldn't Open Your Library").font(IterFont.titleSection)
                Text(failure.message).textSelection(.enabled)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Backup Folder").font(IterFont.captionStrong).foregroundStyle(IterColor.textSecondary)
                    Text(failure.backupFolder.path(percentEncoded: false)).font(IterFont.secondary).textSelection(.enabled)
                }
            }
            .padding(IterSpace.sheet)
            .frame(maxWidth: 560, alignment: .leading)
        }
    }
}

/// The one-time notice after Iter rebuilt the library from a backup.
struct IOSRecoveryNoticeView: View {
    let info: RecoveryInfo
    let dismiss: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: IterSpace.lg) {
                    Image(systemName: "externaldrive.badge.checkmark")
                        .font(.largeTitle)
                        .foregroundStyle(IterColor.accent)
                        .accessibilityHidden(true)
                    Text("Iter Rebuilt Your Library From a Backup").font(IterFont.titleSection)
                    Text("Iter couldn't open your library the way it was saved, so it made a new one from the latest backup. Your original files were left exactly as they were, and the backup is still on this device.")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Backup Folder").font(IterFont.captionStrong).foregroundStyle(IterColor.textSecondary)
                        Text(info.backupFolder.path(percentEncoded: false)).font(IterFont.secondary).textSelection(.enabled)
                    }
                    if !info.skippedFiles.isEmpty {
                        Text("These backup files couldn't be read, so they aren't in the new library: \(info.skippedFiles.joined(separator: ", ")).")
                            .font(IterFont.secondary)
                            .foregroundStyle(IterColor.warning)
                    }
                }
                .padding(IterSpace.sheet)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK", action: dismiss) } }
        }
        .interactiveDismissDisabled()
    }
}
