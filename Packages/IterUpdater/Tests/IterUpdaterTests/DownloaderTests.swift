import Foundation
import Synchronization
import Testing
@testable import IterUpdater

/// Serves canned responses by URL so the tests never touch the network.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    struct Route: Sendable {
        var status = 200
        var body = Data()
        var contentLength: Bool = true
        var redirectTo: String?
    }

    static let routes = Mutex<[String: Route]>([:])
    static func register(_ url: String, _ route: Route) { routes.withLock { $0[url] = route } }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let url = request.url, let route = Self.routes.withLock({ $0[url.absoluteString] }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.fileDoesNotExist))
            return
        }
        if let target = route.redirectTo, let targetURL = URL(string: target) {
            let response = HTTPURLResponse(url: url, statusCode: 302, httpVersion: "HTTP/1.1", headerFields: ["Location": target])!
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: targetURL), redirectResponse: response)
            return
        }
        var headers: [String: String] = [:]
        if route.contentLength { headers["Content-Length"] = String(route.body.count) }
        let response = HTTPURLResponse(url: url, statusCode: route.status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        let step = 16 * 1024
        var offset = 0
        while offset < route.body.count {
            client?.urlProtocol(self, didLoad: route.body.subdata(in: offset..<min(offset + step, route.body.count)))
            offset += step
        }
        client?.urlProtocolDidFinishLoading(self)
    }
}

@Suite("Downloader")
struct DownloaderTests {
    let keys = UpdateSigning.generateKeyPair()

    private func archiveBytes(_ size: Int = 300_000) -> Data {
        Data((0..<size).map { UInt8(truncatingIfNeeded: $0 &* 7 &+ ($0 >> 8)) })
    }

    private func item(for data: Data, url: String, dir: TempDir) throws -> UpdateItem {
        let file = dir.child("source.zip")
        try data.write(to: file)
        return try makeItem(for: file, version: "0.2.0", build: 2, privateKey: keys.privateKey, url: URL(string: url)!)
    }

    private func updater(_ dir: TempDir, feed: String) throws -> Updater {
        let app = try makeBundle(in: dir.url, version: "0.1.0", build: 1)
        return makeUpdater(
            bundle: app, publicKey: keys.publicKey, workDirectory: dir.child("work"),
            feedURL: URL(string: feed)!, session: StubURLProtocol.session())
    }

    @Test func checkForUpdateReadsFeed() async throws {
        let dir = try TempDir()
        let feedURL = "https://feed-ok.test/appcast.json"
        StubURLProtocol.register(feedURL, .init(body: Data(sampleFeedJSON.utf8)))
        let update = try await updater(dir, feed: feedURL).checkForUpdate()
        #expect(update?.version == SemanticVersion("0.2.0"))
        let skipped = try await updater(dir, feed: feedURL).checkForUpdate(skipping: SemanticVersion("0.2.0"))
        #expect(skipped == nil)
    }

    @Test func feedFollowsRedirects() async throws {
        let dir = try TempDir()
        StubURLProtocol.register("https://redirect.test/latest/appcast.json", .init(redirectTo: "https://redirect.test/real/appcast.json"))
        StubURLProtocol.register("https://redirect.test/real/appcast.json", .init(body: Data(sampleFeedJSON.utf8)))
        let update = try await updater(dir, feed: "https://redirect.test/latest/appcast.json").checkForUpdate()
        #expect(update != nil)
    }

    @Test func http404IsFeedUnavailable() async throws {
        let dir = try TempDir()
        let feedURL = "https://feed-404.test/appcast.json"
        StubURLProtocol.register(feedURL, .init(status: 404, body: Data("nope".utf8)))
        await #expect(throws: UpdateError.feedUnavailable("Feed returned HTTP 404")) {
            try await updater(dir, feed: feedURL).checkForUpdate()
        }
    }

    @Test func invalidJSONIsFeedInvalid() async throws {
        let dir = try TempDir()
        let feedURL = "https://feed-bad.test/appcast.json"
        StubURLProtocol.register(feedURL, .init(body: Data("<html>".utf8)))
        await #expect {
            try await updater(dir, feed: feedURL).checkForUpdate()
        } throws: { error in
            if case UpdateError.feedInvalid = error { return true }
            return false
        }
    }

    @Test func networkFailureIsFeedUnavailable() async throws {
        let dir = try TempDir()
        await #expect {
            try await updater(dir, feed: "https://unregistered.test/appcast.json").checkForUpdate()
        } throws: { error in
            if case UpdateError.feedUnavailable = error { return true }
            return false
        }
    }

    @Test func downloadReportsProgressAndVerifies() async throws {
        let dir = try TempDir()
        let data = archiveBytes()
        let url = "https://dl-ok.test/Iter-0.2.0.zip"
        StubURLProtocol.register(url, .init(body: data))
        let item = try item(for: data, url: url, dir: dir)
        let values = Mutex<[Double]>([])
        let file = try await updater(dir, feed: "https://x.test/f.json").downloadAndVerify(item) { fraction in
            values.withLock { $0.append(fraction) }
        }
        #expect(try Data(contentsOf: file) == data)
        let seen = values.withLock { $0 }
        #expect(seen.first == 0)
        #expect(seen.last == 1)
        #expect(seen.count > 3)
        #expect(seen == seen.sorted())
    }

    @Test func unknownLengthReportsMinusOne() async throws {
        let dir = try TempDir()
        let data = archiveBytes(50_000)
        let url = "https://dl-nolength.test/Iter.zip"
        StubURLProtocol.register(url, .init(body: data, contentLength: false))
        let item = try item(for: data, url: url, dir: dir)
        let values = Mutex<[Double]>([])
        _ = try await updater(dir, feed: "https://x.test/f.json").downloadAndVerify(item) { fraction in
            values.withLock { $0.append(fraction) }
        }
        #expect(values.withLock { $0 } == [-1, 1])
    }

    @Test func download404() async throws {
        let dir = try TempDir()
        let data = archiveBytes(1000)
        let url = "https://dl-404.test/Iter.zip"
        StubURLProtocol.register(url, .init(status: 404))
        let item = try item(for: data, url: url, dir: dir)
        await #expect(throws: UpdateError.feedUnavailable("Download returned HTTP 404")) {
            try await updater(dir, feed: "https://x.test/f.json").downloadAndVerify(item) { _ in }
        }
        let work = dir.child("work")
        #expect(((try? FileManager.default.contentsOfDirectory(atPath: work.path)) ?? []).isEmpty)
    }

    @Test func tamperedDownloadIsDeleted() async throws {
        let dir = try TempDir()
        let data = archiveBytes(40_000)
        var served = data
        served[100] ^= 0xFF
        let url = "https://dl-tamper.test/Iter.zip"
        StubURLProtocol.register(url, .init(body: served))
        let item = try item(for: data, url: url, dir: dir)
        await #expect(throws: UpdateError.hashMismatch) {
            try await updater(dir, feed: "https://x.test/f.json").downloadAndVerify(item) { _ in }
        }
        #expect(((try? FileManager.default.contentsOfDirectory(atPath: dir.child("work").path)) ?? []).isEmpty)
    }

    @Test func truncatedDownloadIsSizeMismatch() async throws {
        let dir = try TempDir()
        let data = archiveBytes(40_000)
        let url = "https://dl-short.test/Iter.zip"
        StubURLProtocol.register(url, .init(body: data.prefix(1000)))
        let item = try item(for: data, url: url, dir: dir)
        await #expect(throws: UpdateError.sizeMismatch(expected: 40_000, actual: 1000)) {
            try await updater(dir, feed: "https://x.test/f.json").downloadAndVerify(item) { _ in }
        }
    }

    @Test func downloadWithoutKeyIsBlocked() async throws {
        let dir = try TempDir()
        let app = try makeBundle(in: dir.url, version: "0.1.0", build: 1)
        let updater = makeUpdater(bundle: app, publicKey: nil, workDirectory: dir.child("work"), session: StubURLProtocol.session())
        let item = try item(for: archiveBytes(10), url: "https://dl-nokey.test/a.zip", dir: dir)
        await #expect(throws: UpdateError.blocked(.missingPublicKey)) { try await updater.downloadAndVerify(item) { _ in } }
    }

    @Test func configurationFromBundleOverrides() throws {
        let dir = try TempDir()
        let app = try makeBundle(in: dir.url, version: "0.1.0", build: 7)
        // The dummy bundle has no feed URL, so there is no configuration until defaults supply one.
        let bundle = try #require(Bundle(url: app))
        let defaults = try #require(UserDefaults(suiteName: "IterUpdaterTests-\(UUID().uuidString)"))
        #expect(UpdaterConfiguration.fromBundle(bundle, defaults: defaults) == nil)
        defaults.set("https://override.test/appcast.json", forKey: "IterUpdateFeedURL")
        let configuration = try #require(UpdaterConfiguration.fromBundle(bundle, defaults: defaults))
        #expect(configuration.feedURL.absoluteString == "https://override.test/appcast.json")
        #expect(configuration.channel == "release")
        #expect(configuration.currentVersion.build == 7)
        #expect(configuration.publicKey == nil)
        #expect(configuration.requireValidCodeSignature)
        #expect(configuration.workDirectory.path.hasSuffix("studio.test.iter/Updates"))
    }
}
