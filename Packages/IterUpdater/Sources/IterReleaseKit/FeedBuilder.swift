import Foundation
import IterUpdater

public enum FeedBuilder {
    /// Builds a feed item, measuring the archive so length and hash can never disagree with the file shipped.
    public static func item(
        archive: URL, version: SemanticVersion, build: Int, channel: String = "release",
        minimumSystemVersion: String = "26.0", url: URL, signature: String, publishedAt: Date,
        notarized: Bool = false, notes: String, notesURL: URL? = nil
    ) throws -> UpdateItem {
        let attributes = try FileManager.default.attributesOfItem(atPath: archive.path)
        let length = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        return UpdateItem(
            version: version, build: build, channel: channel, minimumSystemVersion: minimumSystemVersion,
            url: url, length: length, sha256: try UpdateVerifier.sha256Hex(ofFileAt: archive),
            edSignature: signature, publishedAt: publishedAt, notarized: notarized, notes: notes, notesURL: notesURL)
    }

    /// Prepends `item` and drops any earlier item with the same version, so re-running a release replaces it.
    public static func merge(_ item: UpdateItem, into previous: UpdateFeed?) -> UpdateFeed {
        UpdateFeed(items: [item] + (previous?.items ?? []).filter { $0.version != item.version })
    }
}
