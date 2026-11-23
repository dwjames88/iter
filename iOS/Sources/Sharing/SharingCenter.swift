import Foundation
import Observation
import SwiftUI
import UniformTypeIdentifiers
import CoreTransferable
import IterFeatures
import IterStore

// OWNER: W4 (settings and sharing). CONTRACT members are used by the shell (W1) and the screens (W3).

/// A file read and waiting for "Merge" or "Import as Copy".
struct PendingIterFile: Equatable, Identifiable {
    var id = UUID()
    var name: String
    var data: Data
    /// A v1 file has no ids to merge by, so it can only come in as copies.
    var isV1: Bool
}

/// What the result alert says.
struct SharingNotice: Equatable, Identifiable {
    var id = UUID()
    var title: String
    var message: String
}

/// Getting trips on and off the phone: opening `.iter` files (Files, AirDrop, share sheet, the importer), the
/// merge-or-copy choice, and the outcome notice.
@MainActor @Observable
final class SharingCenter {
    @ObservationIgnored let library: LibraryModel
    var showsImporter = false
    /// Set when a file has been read; the choice dialog shows while it is non-nil.
    var pending: PendingIterFile?
    var notice: SharingNotice?

    init(library: LibraryModel) { self.library = library }

    /// CONTRACT: opens a file URL handed to the app (onOpenURL). True when it was an `.iter` file (the shell ignores it then).
    @discardableResult
    func open(_ url: URL) -> Bool {
        guard Self.isIterFile(url) else { return false }
        read(url)
        return true
    }

    /// CONTRACT: shows the file importer.
    func beginImport() { showsImporter = true }

    /// The importer's result.
    func chooseImport(_ result: Result<URL, any Error>) {
        switch result {
        case .failure(let error): notice = SharingNotice(title: "Couldn't Import Trip", message: error.localizedDescription)
        case .success(let url): read(url)
        }
    }

    /// Imports the waiting file: a merge (by id, newer edit wins, deletions carry over) or as new copies.
    func perform(_ file: PendingIterFile, asCopy: Bool) {
        pending = nil
        do {
            let summary = try library.importLibrary(file.data, asCopy: asCopy)
            notice = SharingNotice(title: "Import Finished", message: ImportText.summary(summary, fileName: file.name))
        } catch {
            notice = SharingNotice(title: "Couldn't Import Trip", message: ImportText.reason(for: error))
        }
    }

    static func isIterFile(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        if url.pathExtension.lowercased() == "iter" { return true }
        if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType { return type.conforms(to: .iterTrip) }
        return false
    }

    /// Reads under security scope, then removes the copy iOS put in the app's Inbox (AirDrop, Files and the share sheet hand
    /// the app a copy).
    private func read(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let isV1: Bool
            if case .v1? = try? ITERFile.read(data) { isV1 = true } else { isV1 = false }
            pending = PendingIterFile(name: url.deletingPathExtension().lastPathComponent, data: data, isV1: isV1)
            if Self.isInbox(url) { try? FileManager.default.removeItem(at: url) }
        } catch {
            notice = SharingNotice(title: "Couldn't Import Trip", message: error.localizedDescription)
        }
    }

    static func isInbox(_ url: URL) -> Bool { url.deletingLastPathComponent().lastPathComponent == "Inbox" }
}

extension View {
    /// CONTRACT: attaches the importer, the "Merge / Import as Copy" choice and the result alert. The shell applies it once
    /// at the root.
    func sharingFlows(_ center: SharingCenter) -> some View { modifier(SharingFlows(center: center)) }
}

private struct SharingFlows: ViewModifier {
    @Bindable var center: SharingCenter

    func body(content: Content) -> some View {
        content
            .fileImporter(isPresented: $center.showsImporter, allowedContentTypes: [.iterTrip, .json]) { center.chooseImport($0) }
            .confirmationDialog(
                center.pending.map { "Add \u{201C}\($0.name)\u{201D}?" } ?? "Add Trip?",
                isPresented: Binding(get: { center.pending != nil }, set: { if !$0 { center.pending = nil } }),
                titleVisibility: .visible, presenting: center.pending
            ) { file in
                if file.isV1 {
                    Button("Import as Copy") { center.perform(file, asCopy: true) }
                } else {
                    Button("Merge") { center.perform(file, asCopy: false) }
                    Button("Import as Copy") { center.perform(file, asCopy: true) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { file in
                Text(file.isV1
                     ? "This is an older Iter file, so it can only be added as a copy."
                     : "Merge updates trips you already have and adds new ones. Import as Copy adds everything as new trips.")
            }
            .alert(center.notice?.title ?? "", isPresented: Binding(get: { center.notice != nil }, set: { if !$0 { center.notice = nil } })) {
                Button("OK") { center.notice = nil }
            } message: {
                Text(center.notice?.message ?? "")
            }
    }
}

// MARK: - Export

/// An `.iter` v2 file built when the share is performed, never in a view body.
struct IterFileExport: Transferable {
    struct Unavailable: Error {}
    var fileName: String
    var build: @MainActor @Sendable () -> ExportedLibrary?

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .iterTrip) { item in
            let file = await MainActor.run { item.build() }
            guard let file else { throw Unavailable() }
            return file.data
        }
        .suggestedFileName { $0.fileName }
    }
}

/// CONTRACT: shares one trip as an `.iter` v2 file (AirDrop first in the share sheet).
struct ShareTripButton: View {
    let tripID: UUID
    let library: LibraryModel

    var body: some View {
        let name = library.tripRow(id: tripID)?.name ?? "Trip"
        let item = IterFileExport(fileName: ITERFileInfo.suggestedFileName(forTripNamed: name)) { [library, tripID] in
            try? library.exportTrip(tripID)
        }
        ShareLink(item: item, preview: SharePreview(name)) { Label("Share Trip", systemImage: "square.and.arrow.up") }
    }
}

/// CONTRACT: shares the whole library as an `.iter` v2 file.
struct ShareLibraryButton: View {
    let library: LibraryModel

    var body: some View {
        let item = IterFileExport(fileName: "Iter Library.iter") { [library] in try? library.exportLibrary() }
        ShareLink(item: item, preview: SharePreview("Iter Library")) { Label("Share Library", systemImage: "square.and.arrow.up") }
    }
}
