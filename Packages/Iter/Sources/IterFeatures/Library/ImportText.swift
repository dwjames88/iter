import Foundation

/// The sentences of the import flow, shared by the Mac and iPhone apps.
public enum ImportText {
    public static func summary(_ s: ImportSummary, fileName: String) -> String {
        if s.isEmpty { return "\"\(fileName)\" is already in your library. Nothing changed." }
        var parts: [String] = []
        if s.tripsAdded > 0 { parts.append("added \(count(s.tripsAdded, "trip"))") }
        if s.tripsUpdated > 0 { parts.append("updated \(count(s.tripsUpdated, "trip"))") }
        if s.tripsRemoved > 0 { parts.append("removed \(count(s.tripsRemoved, "trip")) that were deleted elsewhere") }
        if s.placesAdded > 0 { parts.append("added \(count(s.placesAdded, "place"))") }
        if s.foldersAdded > 0 { parts.append("added \(count(s.foldersAdded, "folder"))") }
        var text = parts.joined(separator: ", ")
        text = text.prefix(1).uppercased() + text.dropFirst() + "."
        if s.asCopy { text += " Everything came in as new copies." }
        return text
    }

    public static func reason(for error: any Error) -> String {
        "That file isn't an Iter trip Iter can read. (\(error.localizedDescription))"
    }

    private static func count(_ n: Int, _ noun: String) -> String { n == 1 ? "1 \(noun)" : "\(n) \(noun)s" }
}
