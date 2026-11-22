import Foundation
import IterCore

/// Reddit search, as posts. Free, no key, read-only JSON. Reddit often refuses unknown clients (403) or limits them
/// (429); both become "Rate limited". Posts are text for the extractor, never places.
public struct RedditSource: DiscoveryTextSource {
    public static let globalEndpoint = "https://www.reddit.com/search.json"
    /// Photography and outdoors subreddits searched together (a multireddit), restricted to their own posts.
    public static let subreddits = ["EarthPorn", "itookapicture", "photography", "landscapephotography", "NationalPark", "hiking"]
    public static let postLimit = 25

    public let id = DiscoverySourceID.reddit
    private let http: DiscoveryHTTP

    public init(http: DiscoveryHTTP) { self.http = http }

    public func texts(in area: DiscoveryArea, feature: FeatureKind?, text: String?, settings: DiscoverySettings) async throws -> [DiscoveryText] {
        try await posts(in: area, feature: feature, text: text)
    }

    /// Posts from a site-wide search, the photography multireddit, and the area's own subreddit (guessed from its
    /// name, e.g. r/GlacierNationalPark; a missing one is ignored). Throws only if every request failed.
    public func posts(in area: DiscoveryArea, feature: FeatureKind?, text: String?) async throws -> [DiscoveryText] {
        let terms = DiscoveryQuery.terms(area: area, feature: feature, text: text)
        var urls: [URL?] = [
            DiscoveryHTTP.url(Self.globalEndpoint, [("q", terms), ("limit", "\(Self.postLimit)"), ("sort", "relevance"), ("t", "all"), ("raw_json", "1")]),
            DiscoveryHTTP.url("https://www.reddit.com/r/" + Self.subreddits.joined(separator: "+") + "/search.json",
                              [("q", terms), ("restrict_sr", "1"), ("limit", "\(Self.postLimit)"), ("sort", "relevance"), ("t", "all"), ("raw_json", "1")]),
        ]
        if let sub = Self.guessSubreddit(area.name) {
            let q = feature?.pluralName ?? (text?.isEmpty == false ? text! : "photography")
            urls.append(DiscoveryHTTP.url("https://www.reddit.com/r/\(sub)/search.json",
                                          [("q", q), ("restrict_sr", "1"), ("limit", "\(Self.postLimit)"), ("sort", "relevance"), ("t", "all"), ("raw_json", "1")]))
        }
        var posts: [DiscoveryText] = []
        var firstError: (any Error)?
        var succeeded = false
        for (index, url) in urls.enumerated() {
            guard let url else { continue }
            try Task.checkCancellation()
            do {
                let data = try await http.get(url, host: .reddit)
                succeeded = true
                posts += try RedditParser.posts(data)
            } catch DiscoveryError.notFound where index == 2 {
                succeeded = true   // no such subreddit: the server answered, nothing to add
            } catch {
                if error is CancellationError { throw error }
                firstError = firstError ?? error
                if case DiscoveryError.rateLimited = error { break }   // keep the 2 s politeness; do not push a limited client
            }
        }
        if !succeeded, let firstError { throw firstError }
        var seen = Set<URL>()
        return posts.filter { post in post.url.map { seen.insert($0).inserted } ?? true }
    }

    /// "Glacier National Park" -> "GlacierNationalPark". Nil for names with no usable letters.
    static func guessSubreddit(_ name: String?) -> String? {
        guard let name else { return nil }
        let joined = name.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map { word -> String in
            word.prefix(1).uppercased() + word.dropFirst()
        }.joined()
        return (3...21).contains(joined.count) ? joined : nil
    }
}

enum RedditParser {
    /// `t3` (link) children of a listing. NSFW posts are left out.
    static func posts(_ data: Data) throws -> [DiscoveryText] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw DiscoveryError.badResponse }
        guard let children = (root["data"] as? [String: Any])?["children"] as? [[String: Any]] else { throw DiscoveryError.badResponse }
        return children.compactMap { child in
            guard child["kind"] as? String == "t3", let post = child["data"] as? [String: Any],
                  let title = post["title"] as? String, !title.isEmpty, (post["over_18"] as? Bool) != true else { return nil }
            let body = ((post["selftext"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let permalink = post["permalink"] as? String
            return DiscoveryText(source: .reddit, title: title, body: String(body.prefix(600)),
                                 score: max(0, (post["score"] as? NSNumber)?.intValue ?? 0),
                                 url: permalink.flatMap { URL(string: "https://www.reddit.com" + $0) })
        }
    }
}

/// Google Programmable Search (Custom Search JSON API), only with the user's own key and engine id. Without both,
/// `readiness()` says `.needsKey` and no request is made. Results are title and snippet text for the extractor.
public struct GoogleSearchSource: DiscoveryTextSource {
    public static let endpoint = "https://www.googleapis.com/customsearch/v1"

    public let id = DiscoverySourceID.google
    private let http: DiscoveryHTTP
    private let keys: any DiscoveryKeyStore

    public init(http: DiscoveryHTTP, keys: any DiscoveryKeyStore) {
        self.http = http
        self.keys = keys
    }

    public func readiness() -> DiscoverySourceStatus? { keys.hasGoogleCredentials ? nil : .needsKey }

    public func texts(in area: DiscoveryArea, feature: FeatureKind?, text: String?, settings: DiscoverySettings) async throws -> [DiscoveryText] {
        guard keys.hasGoogleCredentials, let key = keys.googleAPIKey?.trimmingCharacters(in: .whitespaces),
              let engine = keys.googleEngineID?.trimmingCharacters(in: .whitespaces) else { throw DiscoveryError.unavailable("No key") }
        let q = "best photography spots " + DiscoveryQuery.terms(area: area, feature: feature, text: text)
        guard let url = DiscoveryHTTP.url(Self.endpoint, [("key", key), ("cx", engine), ("q", q), ("num", "10")]) else { throw DiscoveryError.badResponse }
        do {
            let data = try await http.get(url, host: .google)
            return try GoogleParser.results(data)
        } catch {
            if error is CancellationError { throw error }
            throw DiscoveryError.map(error, redacting: [key, engine])
        }
    }
}

enum GoogleParser {
    static func results(_ data: Data) throws -> [DiscoveryText] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw DiscoveryError.badResponse }
        if root["error"] != nil { throw DiscoveryError.badResponse }
        let items = (root["items"] as? [[String: Any]]) ?? []
        return items.compactMap { item in
            guard let title = item["title"] as? String, !title.isEmpty else { return nil }
            return DiscoveryText(source: .google, title: title, body: (item["snippet"] as? String) ?? "",
                                 url: (item["link"] as? String).flatMap(URL.init(string:)))
        }
    }
}
