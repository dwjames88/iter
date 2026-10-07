import Foundation

public struct UpdateItem: Codable, Hashable, Sendable, Identifiable {
    public var version: SemanticVersion
    public var build: Int
    public var channel: String
    public var minimumSystemVersion: String
    public var url: URL
    public var length: Int64
    public var sha256: String
    public var edSignature: String
    public var publishedAt: Date
    public var notarized: Bool
    public var notes: String
    public var notesURL: URL?

    public init(
        version: SemanticVersion, build: Int, channel: String = "release", minimumSystemVersion: String = "26.0",
        url: URL, length: Int64, sha256: String, edSignature: String, publishedAt: Date,
        notarized: Bool = false, notes: String = "", notesURL: URL? = nil
    ) {
        self.version = version
        self.build = build
        self.channel = channel
        self.minimumSystemVersion = minimumSystemVersion
        self.url = url
        self.length = length
        self.sha256 = sha256
        self.edSignature = edSignature
        self.publishedAt = publishedAt
        self.notarized = notarized
        self.notes = notes
        self.notesURL = notesURL
    }

    public var appVersion: AppVersion { AppVersion(version: version, build: build) }
    public var id: String { "\(version)+\(build)" }

    private enum CodingKeys: String, CodingKey {
        case version, build, channel, minimumSystemVersion, url, length, sha256, edSignature
        case publishedAt, notarized, notes, notesURL
    }

    /// Cosmetic fields are optional so a hand-edited feed still loads; the fields that gate trust are required.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(SemanticVersion.self, forKey: .version)
        build = try c.decode(Int.self, forKey: .build)
        channel = try c.decodeIfPresent(String.self, forKey: .channel) ?? "release"
        minimumSystemVersion = try c.decodeIfPresent(String.self, forKey: .minimumSystemVersion) ?? "0"
        url = try c.decode(URL.self, forKey: .url)
        length = try c.decode(Int64.self, forKey: .length)
        sha256 = try c.decode(String.self, forKey: .sha256)
        edSignature = try c.decode(String.self, forKey: .edSignature)
        publishedAt = try c.decode(Date.self, forKey: .publishedAt)
        notarized = try c.decodeIfPresent(Bool.self, forKey: .notarized) ?? false
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        notesURL = try c.decodeIfPresent(URL.self, forKey: .notesURL)
    }

    /// True when `system` meets `minimumSystemVersion` ("26", "26.0", "26.1.2"). An unparsable minimum is
    /// treated as unsatisfied: better to offer nothing than something that will not launch.
    func isSupported(on system: OperatingSystemVersion) -> Bool {
        let parts = minimumSystemVersion.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !parts.isEmpty, parts.count <= 3, !parts.contains(nil) else { return false }
        let numbers = parts.compactMap { $0 } + Array(repeating: 0, count: 3 - parts.count)
        let required = (numbers[0], numbers[1], numbers[2])
        return required <= (system.majorVersion, system.minorVersion, system.patchVersion)
    }
}

public struct UpdateFeed: Codable, Hashable, Sendable {
    public static let schemaVersion = 1

    public var schemaVersion: Int
    public var items: [UpdateItem]

    public init(items: [UpdateItem]) {
        self.schemaVersion = Self.schemaVersion
        self.items = items
    }

    private enum CodingKeys: String, CodingKey { case schemaVersion, items }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? Self.schemaVersion
        items = try c.decode([UpdateItem].self, forKey: .items)
    }

    /// A newer schemaVersion still decodes: unknown keys are ignored, and the fields we need are stable.
    public static func decode(_ data: Data) throws -> UpdateFeed {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let string = try decoder.singleValueContainer().decode(String.self)
            if let date = try? Date.ISO8601FormatStyle().parse(string) { return date }
            if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(string) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid date \"\(string)\""))
        }
        do {
            return try decoder.decode(UpdateFeed.self, from: data)
        } catch {
            throw UpdateError.feedInvalid(String(describing: error))
        }
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.ISO8601Format())
        }
        var data = try encoder.encode(self)
        data.append(0x0A)
        return data
    }

    /// The newest item that is on `channel`, runs on `system`, is newer than `current` and is not the version
    /// the user chose to skip.
    public func bestUpdate(
        newerThan current: AppVersion,
        channel: String,
        system: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion,
        skipping: SemanticVersion? = nil
    ) -> UpdateItem? {
        items
            .filter { $0.channel == channel }
            .filter { $0.isSupported(on: system) }
            .filter { $0.appVersion > current }
            .filter { $0.version != skipping }
            .max { $0.appVersion < $1.appVersion }
    }
}
