import Foundation
import IterUpdater

public enum ChangelogError: Error, Equatable, Sendable, CustomStringConvertible {
    case missingUnreleased
    case emptyUnreleased
    case invalidVersion(String)
    case invalidDate(String)
    case versionAlreadyReleased(String)

    public var description: String {
        switch self {
        case .missingUnreleased: "CHANGELOG has no \"## [Unreleased]\" heading."
        case .emptyUnreleased: "The Unreleased section is empty; nothing to release."
        case .invalidVersion(let v): "\"\(v)\" is not a valid version."
        case .invalidDate(let d): "\"\(d)\" is not a YYYY-MM-DD date."
        case .versionAlreadyReleased(let v): "Version \(v) already has a section in the CHANGELOG."
        }
    }
}

/// Keep a Changelog 1.1.0 text: `## [Unreleased]`, `## [0.1.0] - 2026-10-06`, link references at the bottom.
public struct Changelog: Sendable {
    public static let defaultRepository = "https://github.com/dwjames88/iter"

    public var text: String

    public init(_ text: String) {
        self.text = text
    }

    /// Moves the body of Unreleased under a new dated heading, leaves an empty Unreleased above it and updates
    /// the link references.
    public func releasing(
        version rawVersion: String, date: String, repository: String = Changelog.defaultRepository
    ) throws -> String {
        guard let parsed = SemanticVersion(rawVersion) else { throw ChangelogError.invalidVersion(rawVersion) }
        guard date.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else {
            throw ChangelogError.invalidDate(date)
        }
        let version = parsed.description
        var lines = text.components(separatedBy: "\n")
        guard let start = lines.firstIndex(where: { Self.isHeading($0, "Unreleased") }) else {
            throw ChangelogError.missingUnreleased
        }
        if lines.contains(where: { Self.isHeading($0, version) }) { throw ChangelogError.versionAlreadyReleased(version) }

        let end = Self.sectionEnd(after: start, in: lines)
        let body = Self.trimBlankEdges(Array(lines[(start + 1)..<end]))
        // Bare "### Added" headings are scaffolding, not content.
        guard body.contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty && !$0.hasPrefix("###") }) else {
            throw ChangelogError.emptyUnreleased
        }

        // The previous release is the next versioned heading below Unreleased.
        let previous = lines[end...].compactMap(Self.versionOfHeading).first

        var replacement = ["## [Unreleased]", "", "## [\(version)] - \(date)", ""]
        replacement += body
        replacement.append("")
        lines.replaceSubrange(start..<end, with: replacement)

        let unreleasedLink = "[Unreleased]: \(repository)/compare/v\(version)...HEAD"
        let versionLink = previous.map { "[\(version)]: \(repository)/compare/v\($0)...v\(version)" }
            ?? "[\(version)]: \(repository)/releases/tag/v\(version)"
        Self.updateLinks(in: &lines, unreleased: unreleasedLink, version: version, versionLink: versionLink)
        return lines.joined(separator: "\n")
    }

    /// The body of `## [version]` without its heading, trimmed of blank edges; nil when there is no such section.
    public func section(version rawVersion: String) -> String? {
        let version = SemanticVersion(rawVersion)?.description ?? rawVersion
        let lines = text.components(separatedBy: "\n")
        guard let start = lines.firstIndex(where: { Self.isHeading($0, version) }) else { return nil }
        let end = Self.sectionEnd(after: start, in: lines)
        return Self.trimBlankEdges(Array(lines[(start + 1)..<end])).joined(separator: "\n")
    }

    // MARK: Parsing

    private static func isHeading(_ line: String, _ name: String) -> Bool {
        line == "## [\(name)]" || line.hasPrefix("## [\(name)] ")
    }

    private static func versionOfHeading(_ line: String) -> String? {
        guard line.hasPrefix("## ["), let close = line.firstIndex(of: "]") else { return nil }
        let name = String(line[line.index(line.startIndex, offsetBy: 4)..<close])
        return name == "Unreleased" ? nil : SemanticVersion(name)?.description
    }

    private static func isLinkReference(_ line: String) -> Bool {
        line.range(of: #"^\[[^\]]+\]:\s"#, options: .regularExpression) != nil
    }

    /// A section runs to the next `## ` heading or to the link-reference block at the bottom.
    private static func sectionEnd(after start: Int, in lines: [String]) -> Int {
        var index = start + 1
        while index < lines.count, !lines[index].hasPrefix("## "), !isLinkReference(lines[index]) { index += 1 }
        return index
    }

    private static func trimBlankEdges(_ lines: [String]) -> [String] {
        var result = lines[...]
        while let first = result.first, first.trimmingCharacters(in: .whitespaces).isEmpty { result = result.dropFirst() }
        while let last = result.last, last.trimmingCharacters(in: .whitespaces).isEmpty { result = result.dropLast() }
        return Array(result)
    }

    private static func updateLinks(in lines: inout [String], unreleased: String, version: String, versionLink: String) {
        lines.removeAll { $0.hasPrefix("[\(version)]:") }
        if let index = lines.firstIndex(where: { $0.hasPrefix("[Unreleased]:") }) {
            lines[index] = unreleased
            lines.insert(versionLink, at: index + 1)
            return
        }
        // No link block yet: start one at the end, separated by a blank line, keeping a trailing newline.
        while let last = lines.last, last.isEmpty { lines.removeLast() }
        lines += ["", unreleased, versionLink, ""]
    }
}
