import Foundation
import IterAI
import IterModel
import IterSources

/// The "why" line for a result (BLUEPRINT §7 step 8). The model sees only the place's stored facts; its sentence is used
/// only when every number in it is in the facts (ported from `LightExplainer`) and every capitalised word is in the facts
/// too. Otherwise a template sentence built from the same facts is used.
struct PlaceExplainer: Sendable {
    var model: (any LanguageModeling)?
    var timeout: Duration
    var sourceNames: [SourceID: String]
    var areaName: String?
    var plan: QueryPlan

    static let instructions = """
    Write one short sentence (at most 25 words) saying why this place fits the search. Use only the facts given. \
    Do not add any number, name, distance or weather that is not in the facts. No hype, no exclamation marks.
    """

    func facts(for place: DiscoveredPlace) -> String {
        var lines = ["Name: \(place.name)"]
        if !place.featureKinds.isEmpty { lines.append("Kind: " + place.featureKinds.map(\.singularName).joined(separator: ", ")) }
        if let areaName { lines.append("Area: \(areaName)") }
        let names = place.sources.map { sourceNames[$0] ?? $0.rawValue }
        lines.append("Sources: " + names.joined(separator: ", "))
        lines.append("Status: " + status(for: place))
        if place.photoCount > 0 { lines.append("Geotagged photos nearby: \(place.photoCount)") }
        if place.mentionCount > 0 { lines.append("Mentions: \(place.mentionCount)") }
        if let e = place.elevationMeters { lines.append("Elevation: \(Int(e.rounded())) metres") }
        if let d = place.distanceKm { lines.append("Distance: \(Int(d.rounded())) km") }
        if !plan.features.isEmpty { lines.append("Wanted: " + plan.features.map(\.pluralName).joined(separator: ", ")) }
        if !plan.windows.isEmpty { lines.append("Light wanted: " + plan.windows.map(\.rawValue).joined(separator: ", ")) }
        if let s = place.snippet { lines.append("Note: \(s)") }
        return lines.joined(separator: "\n")
    }

    /// A sentence from the facts alone.
    func template(for place: DiscoveredPlace) -> String {
        let kind = place.featureKinds.first.map { $0.singularName.prefix(1).uppercased() + $0.singularName.dropFirst() } ?? "Place"
        var s = kind + (areaName.map { " in \($0)" } ?? "")
        s += ", " + status(for: place)
        if place.photoCount > 0 { s += "; \(place.photoCount) geotagged \(place.photoCount == 1 ? "photo" : "photos") nearby" }
        return s + "."
    }

    /// What confirmed the place, counted honestly: independent source families, or one map source that lists it with a
    /// stable id (OSM, GNIS, a geotagged Wikipedia page), which also counts as confirmed but is said as such.
    func status(for place: DiscoveredPlace) -> String {
        let families = Set(place.sources.map(\.family)).count
        if families >= 2 { return "confirmed by \(families) sources" }
        if place.verification == .confirmed {
            let name = place.sources.first.map { sourceNames[$0] ?? $0.rawValue } ?? "one map source"
            return "listed by \(name)"
        }
        return "reported by one source"
    }

    func explain(_ place: DiscoveredPlace) async -> PlaceExplanation {
        guard let model else { return PlaceExplanation(text: template(for: place), isModelWritten: false) }
        let facts = facts(for: place)
        let prompt = AIPrompt(instructions: Self.instructions, prompt: "Facts:\n\(facts)")
        let limit = timeout
        if let raw = try? await withDeadline(limit, { try await model.respond(prompt: prompt, options: AICallOptions(timeout: limit, maxAttempts: 1, temperature: 0)) }) {
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if Self.isGrounded(output: text, facts: facts) { return PlaceExplanation(text: text, isModelWritten: true) }
        }
        return PlaceExplanation(text: template(for: place), isModelWritten: false)
    }

    // MARK: Checks

    /// One line, not long, every number in the facts, every capitalised word (after the first) in the facts.
    static func isGrounded(output: String, facts: String) -> Bool {
        guard !output.isEmpty, output.count <= 240, !output.contains("\n") else { return false }
        guard numbersAreGrounded(output: output, facts: facts) else { return false }
        return namesAreGrounded(output: output, facts: facts)
    }

    /// Every number in `output` must also appear in `facts`.
    static func numbersAreGrounded(output: String, facts: String) -> Bool {
        let allowed = Set(numbers(in: facts))
        return numbers(in: output).allSatisfy(allowed.contains)
    }

    static func numbers(in text: String) -> [String] {
        var result: [String] = []
        var current = ""
        func flush() { if !current.isEmpty { result.append(current); current = "" } }
        let chars = Array(text)
        for (i, ch) in chars.enumerated() {
            if ch.isNumber, ch.isASCII || ch.wholeNumberValue != nil {
                current.append(ch)
            } else if (ch == "." || ch == ","), !current.isEmpty, i + 1 < chars.count, chars[i + 1].isNumber {
                current.append(".")
            } else {
                flush()
            }
        }
        flush()
        return result
    }

    /// A capitalised word in the sentence (other than its first word) must appear in the facts: no place the facts do not name.
    static func namesAreGrounded(output: String, facts: String) -> Bool {
        let known = Set(DiscoveryNames.tokens(facts))
        let words = output.split(whereSeparator: { $0.isWhitespace })
        for (i, w) in words.enumerated() where i > 0 {
            let stripped = w.trimmingCharacters(in: CharacterSet.letters.inverted)
            guard let first = stripped.unicodeScalars.first, CharacterSet.uppercaseLetters.contains(first) else { continue }
            // A word after a full stop starts a sentence.
            if let previous = words[i - 1].last, ".!?".contains(previous) { continue }
            for t in DiscoveryNames.tokens(stripped) where !known.contains(t) { return false }
        }
        return true
    }
}
