import SwiftUI
import Observation
import IterFeatures
import IterUI

/// The iPhone's undo for list actions: after a delete (or any change worth taking back) a small "Trip Deleted · Undo" capsule
/// floats above the tab bar for a few seconds. Undo goes through the library's own named undo step (`LibraryModel.undoManager`),
/// the same step Edit > Undo takes on the Mac. If the shell has not given the library an undo manager, the toast installs one.
@MainActor @Observable
public final class PhoneUndoToast {
    public struct Item: Identifiable, Equatable, Sendable {
        public let id: UUID
        public let message: String
    }

    public private(set) var current: Item?
    @ObservationIgnored private let library: LibraryModel
    @ObservationIgnored private let lifetime: Duration
    @ObservationIgnored private var dismissTask: Task<Void, Never>?
    /// Held here: the store keeps its undo manager weakly.
    @ObservationIgnored private var ownManager: UndoManager?

    public init(library: LibraryModel, lifetime: Duration = .seconds(6)) {
        self.library = library
        self.lifetime = lifetime
        if library.undoManager == nil {
            let manager = UndoManager()
            ownManager = manager
            library.undoManager = manager
        }
    }

    /// Run `action` (a library change) and offer to undo it.
    public func perform(_ message: String, _ action: () -> Void) {
        action()
        show(message)
    }

    public func show(_ message: String) {
        let item = Item(id: UUID(), message: message)
        current = item
        dismissTask?.cancel()
        dismissTask = Task { [weak self, lifetime] in
            try? await Task.sleep(for: lifetime)
            guard !Task.isCancelled else { return }
            if self?.current?.id == item.id { self?.current = nil }
        }
    }

    /// Takes the last library step back. False when there was nothing to undo.
    @discardableResult
    public func undo() -> Bool {
        dismissTask?.cancel()
        current = nil
        guard let manager = library.undoManager, manager.canUndo else { return false }
        manager.undo()
        library.refresh()
        return true
    }

    public func dismiss() {
        dismissTask?.cancel()
        current = nil
    }
}

private struct UndoToastView: View {
    let toast: PhoneUndoToast

    var body: some View {
        if let item = toast.current {
            GlassEffectContainer {
                HStack(spacing: IterSpace.md) {
                    Text(verbatim: item.message).font(IterFont.bodyEmphasis).foregroundStyle(IterColor.textPrimary)
                    Button { toast.undo() } label: { Text("Undo", comment: "Toast button: take the last action back") }
                        .font(IterFont.bodyEmphasis)
                        .foregroundStyle(IterColor.accentText)
                        .buttonStyle(.plain)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .padding(.leading, IterSpace.lg)
                .padding(.trailing, IterSpace.sm)
                .glassEffect(.regular, in: .capsule)
            }
            .padding(.bottom, IterSpace.sm)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .accessibilityElement(children: .contain)
        }
    }
}

extension View {
    /// Shows the toast's "…· Undo" capsule at the bottom of the view.
    public func phoneUndoToast(_ toast: PhoneUndoToast) -> some View {
        overlay(alignment: .bottom) { UndoToastView(toast: toast) }
            .animation(.snappy, value: toast.current)
    }
}

extension View {
    /// The iPhone sheet's list: inset grouped rows over the sheet's own material (the Mac compiles the package for tests and gets an inset list).
    func phoneGroupedList() -> some View {
        #if os(iOS)
        listStyle(.insetGrouped).scrollContentBackground(.hidden)
        #else
        listStyle(.inset).scrollContentBackground(.hidden)
        #endif
    }
}
