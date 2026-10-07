import Foundation
import Testing
import IterUpdater
@testable import Iter

/// Answers every request with the stub's current response. Tests using it run serially.
final class StubFeedProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var body = Data()
    nonisolated(unsafe) static var requests = 0

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests += 1
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor
@Suite(.serialized) struct UpdateControllerTests {
    static func item(_ version: String, build: Int = 5) -> UpdateItem {
        UpdateItem(version: SemanticVersion(version)!, build: build, url: URL(string: "https://example.com/Iter.zip")!, length: 1000,
                   sha256: String(repeating: "0", count: 64), edSignature: "sig", publishedAt: Date(timeIntervalSince1970: 1_790_000_000),
                   notes: "Notes")
    }

    static func serve(_ items: [UpdateItem], status: Int = 200) throws {
        StubFeedProtocol.status = status
        StubFeedProtocol.body = try UpdateFeed(items: items).encoded()
        StubFeedProtocol.requests = 0
    }

    func controller(publicKey: String? = nil, defaults: UserDefaults? = nil, delay: Duration = .seconds(60)) -> (UpdateController, UserDefaults) {
        let configuration = UpdaterConfiguration(
            feedURL: URL(string: "https://example.com/appcast.json")!, publicKey: publicKey,
            bundleURL: URL(filePath: "/Applications/Iter.app"), bundleIdentifier: "com.test.iter",
            currentVersion: AppVersion(version: SemanticVersion("0.1.0")!, build: 3),
            workDirectory: FileManager.default.temporaryDirectory.appending(path: "iter-update-test-\(UUID().uuidString)"))
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [StubFeedProtocol.self]
        let defaults = defaults ?? UserDefaults(suiteName: "iter.updates.\(UUID().uuidString)")!
        let updater = Updater(configuration: configuration, session: URLSession(configuration: sessionConfiguration))
        return (UpdateController(updater: updater, defaults: defaults, presentsWindow: false, startupDelay: delay, relaunch: { _ in }), defaults)
    }

    @Test func foundUpdateBecomesAvailable() async throws {
        try Self.serve([Self.item("0.2.0")])
        let (c, defaults) = controller()
        await c.check(interactive: true)
        guard case .available(let item) = c.phase else { Issue.record("phase \(c.phase)"); return }
        #expect(item.version.description == "0.2.0")
        #expect(c.lastCheck != nil)
        #expect(defaults.object(forKey: UpdateController.lastCheckKey) is Date)
    }

    @Test func nothingNewIsUpToDate() async throws {
        try Self.serve([Self.item("0.1.0", build: 3)])
        let (c, _) = controller()
        await c.check(interactive: true)
        #expect(c.phase == .upToDate)
    }

    @Test func serverErrorFailsOnlyWhenInteractive() async throws {
        try Self.serve([], status: 500)
        let (c, _) = controller()
        await c.check(interactive: false)
        #expect(c.phase == .idle)
        #expect(c.lastCheck == nil)
        await c.check(interactive: true)
        guard case .failed(let message, nil) = c.phase else { Issue.record("phase \(c.phase)"); return }
        #expect(message == UpdateText.message(for: UpdateError.feedUnavailable("")))
    }

    @Test func skippedVersionIsHiddenFromBackgroundChecksOnly() async throws {
        try Self.serve([Self.item("0.2.0")])
        let (c, defaults) = controller()
        c.skip(Self.item("0.2.0"))
        #expect(defaults.string(forKey: UpdateController.skippedVersionKey) == "0.2.0")
        await c.check(interactive: false)
        #expect(c.phase == .idle)
        await c.check(interactive: true)
        #expect(c.phase == .available(Self.item("0.2.0")))
    }

    @Test func installIsBlockedWithoutAPublicKey() throws {
        let (c, _) = controller(publicKey: nil)
        let item = Self.item("0.2.0")
        c.phase = .available(item)
        c.install(item)
        #expect(c.blockers.contains(.missingPublicKey))
        let first = try #require(c.blockers.first)
        #expect(c.phase == .failed(message: UpdateText.message(for: first), item: item))
    }

    @Test func remindLaterAndDismissReturnToIdle() {
        let (c, _) = controller()
        c.phase = .available(Self.item("0.2.0"))
        c.remindLater()
        #expect(c.phase == .idle)
        c.phase = .upToDate
        c.dismiss()
        #expect(c.phase == .idle)
    }

    @Test func automaticChecksPersistAndDefaultByBuildType() {
        let (c, defaults) = controller()
        #if DEBUG
        #expect(c.automaticChecks == false)
        #else
        #expect(c.automaticChecks == true)
        #endif
        c.automaticChecks = true
        #expect(defaults.bool(forKey: UpdateController.automaticChecksKey))
    }

    @Test func startDoesNothingUnderTests() throws {
        try Self.serve([Self.item("0.2.0")])
        let (c, _) = controller(delay: .zero)
        c.automaticChecks = true
        c.start()
        #expect(StubFeedProtocol.requests == 0)
        #expect(c.phase == .idle)
    }

    @Test func launchCheckRunsWhenDue() async throws {
        try Self.serve([Self.item("0.2.0")])
        let (c, _) = controller(delay: .zero)
        c.automaticChecks = true
        c.beginLaunchWork()
        for _ in 0..<100 where c.lastCheck == nil { try await Task.sleep(for: .milliseconds(50)) }
        #expect(c.lastCheck != nil)
        #expect(c.phase == .available(Self.item("0.2.0")))
    }

    @Test func launchCheckWaitsUntilDueAndHonoursTheSwitch() async throws {
        try Self.serve([Self.item("0.2.0")])
        let recent = UserDefaults(suiteName: "iter.updates.\(UUID().uuidString)")!
        recent.set(Date.now.addingTimeInterval(-3600), forKey: UpdateController.lastCheckKey)
        let (c, _) = controller(defaults: recent, delay: .zero)
        c.automaticChecks = true
        c.beginLaunchWork()
        let (off, _) = controller(delay: .zero)
        off.automaticChecks = false
        off.beginLaunchWork()
        try await Task.sleep(for: .milliseconds(400))
        #expect(StubFeedProtocol.requests == 0)
    }
}
