#if os(macOS)  // Mac only: the direct-download build's updater and store location (the iOS app excludes these)
import AppKit
import SwiftUI
import IterDesign
import IterUpdater

/// The update window's content: an alert-style layout (icon on the left, text and buttons on the right) that
/// follows the controller's phase.
struct UpdateWindowView: View {
    let controller: UpdateController

    var body: some View {
        HStack(alignment: .top, spacing: IterSpace.lg) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: IterSpace.md) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(IterSpace.sheet)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var content: some View {
        switch controller.phase {
        case .idle:
            EmptyView()
        case .checking:
            heading(String(localized: "Checking for updates…", comment: "Update window title while checking"))
            HStack(spacing: IterSpace.sm) {
                ProgressView().controlSize(.small)
                Text("This only takes a moment.", comment: "Update window: checking for updates")
                    .foregroundStyle(IterColor.textSecondary)
            }
            buttons { Button(String(localized: "Cancel", comment: "Update window button")) { controller.cancel(); controller.dismiss() }.keyboardShortcut(.cancelAction) }
        case .upToDate:
            heading(String(localized: "You're up to date", comment: "Update window title: no newer version"))
            Text("Iter \(controller.currentVersionText) is the newest version available.", comment: "Update window: no newer version; the placeholder is the version and build")
            buttons { okButton }
        case .available(let item):
            available(item)
        case .downloading(let fraction):
            progress(title: workingTitle) {
                if let fraction {
                    ProgressView(value: fraction)
                    Text(downloadText(fraction))
                } else {
                    ProgressView()
                    Text("Downloading…", comment: "Update window: download in progress").foregroundStyle(IterColor.textSecondary)
                }
            } buttons: {
                Button(String(localized: "Cancel", comment: "Update window button")) { controller.cancel() }.keyboardShortcut(.cancelAction)
            }
        case .verifying:
            progress(title: workingTitle) { ProgressView(); Text("Verifying…", comment: "Update window: checking the download") } buttons: {}
        case .installing:
            progress(title: workingTitle) { ProgressView(); Text("Installing…", comment: "Update window: replacing the app") } buttons: {}
        case .relaunching:
            progress(title: workingTitle) { ProgressView(); Text("Relaunching…", comment: "Update window: about to restart") } buttons: {}
        case .failed(let message, let item):
            HStack(alignment: .firstTextBaseline, spacing: IterSpace.sm) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(IterColor.warning).accessibilityHidden(true)
                heading(String(localized: "The update didn't finish", comment: "Update window title after a failure"))
            }
            Text(message).fixedSize(horizontal: false, vertical: true)
            buttons {
                Button(String(localized: "Download from GitHub", comment: "Update window button")) { controller.openDownloadPage(for: item) }
                okButton
            }
        }
    }

    // MARK: Pieces

    private var workingTitle: String {
        if let item = controller.workingItem {
            return String(localized: "Updating to Iter \(item.version.description)", comment: "Update window title while installing; the placeholder is a version")
        }
        return String(localized: "Updating Iter", comment: "Update window title while installing")
    }

    private func heading(_ text: String) -> some View {
        Text(text).font(IterFont.titleSection)
    }

    private var okButton: some View {
        Button(String(localized: "OK", comment: "Update window button")) { controller.dismiss() }
            .keyboardShortcut(.defaultAction)
    }

    private func buttons<B: View>(@ViewBuilder _ content: () -> B) -> some View {
        HStack { Spacer(minLength: 0); content() }
    }

    private func progress<P: View, B: View>(title: String, @ViewBuilder _ body: () -> P, @ViewBuilder buttons: () -> B) -> some View {
        VStack(alignment: .leading, spacing: IterSpace.md) {
            heading(title)
            body()
            HStack { Spacer(minLength: 0); buttons() }
        }
    }

    private func downloadText(_ fraction: Double) -> String {
        guard let item = controller.workingItem else { return String(localized: "Downloading…", comment: "Update window: download in progress") }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        let done = formatter.string(fromByteCount: Int64(Double(item.length) * fraction))
        let total = formatter.string(fromByteCount: item.length)
        return String(localized: "Downloading… \(done) of \(total)", comment: "Update window: download progress, e.g. Downloading… 3.2 MB of 12.4 MB")
    }

    private func available(_ item: UpdateItem) -> some View {
        let blockers = controller.blockers
        return VStack(alignment: .leading, spacing: IterSpace.md) {
            heading(String(localized: "A new version of Iter is available", comment: "Update window title"))
            Text("Iter \(item.version.description) is now available — you have \(controller.currentVersionText). Would you like to install it now?",
                 comment: "Update window: the first placeholder is the new version, the second the current version and build")
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: IterSpace.xs) {
                Text("Release Notes", comment: "Update window: heading above the release notes").font(IterFont.bodyEmphasis)
                ScrollView {
                    Text(Self.notes(item.notes))
                        .font(IterFont.footnote)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(IterSpace.sm)
                }
                .frame(height: 200)
                .background(.background)
                .overlay { RoundedRectangle(cornerRadius: IterRadius.badge, style: .continuous).strokeBorder(.separator) }
            }
            if !item.notarized {
                Text("This build is signed but not yet notarised by Apple. Iter installs it directly, so macOS won't ask again.",
                     comment: "Update window: note about an update that Apple has not notarised")
                    .font(IterFont.footnote)
                    .foregroundStyle(IterColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !blockers.isEmpty {
                VStack(alignment: .leading, spacing: IterSpace.xs) {
                    ForEach(blockers, id: \.self) { blocker in
                        Label { Text(UpdateText.message(for: blocker)).fixedSize(horizontal: false, vertical: true) } icon: {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(IterColor.warning)
                        }
                    }
                }
                .font(IterFont.footnote)
            }
            HStack {
                Button(String(localized: "Skip This Version", comment: "Update window button")) { controller.skip(item) }
                Spacer(minLength: IterSpace.md)
                if !blockers.isEmpty {
                    Button(String(localized: "Download from GitHub", comment: "Update window button")) { controller.openDownloadPage(for: item) }
                }
                Button(String(localized: "Remind Me Later", comment: "Update window button")) { controller.remindLater() }
                    .keyboardShortcut(.cancelAction)
                Button(String(localized: "Install and Relaunch", comment: "Update window button")) { controller.install(item) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!blockers.isEmpty)
            }
        }
    }

    /// Release notes are Markdown. Inline syntax with whitespace kept shows bold, links and code, and keeps the
    /// headings and list lines of a changelog readable as written.
    static func notes(_ markdown: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: markdown, options: options)) ?? AttributedString(markdown)
    }
}

#endif
