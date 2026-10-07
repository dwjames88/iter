import Foundation
import CoreTransferable
import UniformTypeIdentifiers

/// What a dragged library row carries: the id of a trip, a saved place or a folder, nothing else.
/// The type is private to Iter; dropping it anywhere else does nothing.
public enum LibraryDragItem: Codable, Hashable, Sendable, Transferable, Identifiable {
    case trip(UUID)
    case place(UUID)
    case folder(UUID)

    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .iterLibraryItem)
    }

    /// The id of the trip, place or folder it names.
    public var id: UUID {
        switch self {
        case .trip(let id), .place(let id), .folder(let id): id
        }
    }

    public var tripID: UUID? { if case .trip(let id) = self { id } else { nil } }
    public var placeID: UUID? { if case .place(let id) = self { id } else { nil } }
    public var folderID: UUID? { if case .folder(let id) = self { id } else { nil } }
}

extension UTType {
    /// In-app drag of a trip, saved place or folder. Not declared in Info.plist on purpose: it never leaves the app.
    public static let iterLibraryItem = UTType(exportedAs: "com.dwjames.iter.library-item")
}

/// Pure naming helpers for the library.
public enum LibraryNaming {
    /// `base` if no existing name equals it (ignoring case and surrounding space), else `base 2`, `base 3`…
    public static func uniqueName(_ base: String, among existing: [String]) -> String {
        let taken = Set(existing.map { $0.trimmingCharacters(in: .whitespaces).lowercased() })
        guard taken.contains(base.lowercased()) else { return base }
        var n = 2
        while taken.contains("\(base) \(n)".lowercased()) { n += 1 }
        return "\(base) \(n)"
    }

    /// A folder name from the user's text: trimmed, nil when empty.
    public static func cleanedName(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
