import Foundation
import Synchronization
@testable import IterSources

/// A scriptable `HTTPTransport`: each call runs the handler with the request and the zero-based call number.
final class FakeTransport: HTTPTransport {
    typealias Handler = @Sendable (URLRequest, Int) async throws -> (Data, HTTPURLResponse)
    private struct State { var requests: [URLRequest] = [] }
    private let state = Mutex(State())
    private let handler: Handler

    init(_ handler: @escaping Handler) { self.handler = handler }

    /// Replies with the given scripted replies in order; the last repeats.
    convenience init(replies: [Reply]) {
        self.init { request, n in
            let r = replies[min(n, replies.count - 1)]
            return try r.make(request)
        }
    }

    var requests: [URLRequest] { state.withLock { $0.requests } }
    var callCount: Int { state.withLock { $0.requests.count } }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let n = state.withLock { s -> Int in
            s.requests.append(request)
            return s.requests.count - 1
        }
        return try await handler(request, n)
    }

    struct Reply: Sendable {
        var make: @Sendable (URLRequest) throws -> (Data, HTTPURLResponse)

        static func status(_ code: Int, body: String = "", headers: [String: String] = [:]) -> Reply {
            Reply { req in
                let url = req.url ?? URL(string: "https://example.invalid/")!
                let resp = HTTPURLResponse(url: url, statusCode: code, httpVersion: "HTTP/1.1", headerFields: headers)!
                return (Data(body.utf8), resp)
            }
        }

        static func error(_ e: URLError.Code) -> Reply { Reply { _ in throw URLError(e) } }
    }
}

/// Counts calls from any task.
final class Counter: Sendable {
    private let n = Mutex(0)
    var value: Int { n.withLock { $0 } }
    @discardableResult func increment() -> Int { n.withLock { $0 += 1; return $0 } }
}

/// Holds callers until opened.
final class Gate: Sendable {
    private struct State { var open = false; var waiters: [CheckedContinuation<Void, Never>] = [] }
    private let state = Mutex(State())

    func wait() async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            let resumeNow = state.withLock { s -> Bool in
                if s.open { return true }
                s.waiters.append(c)
                return false
            }
            if resumeNow { c.resume() }
        }
    }

    func open() {
        let ws = state.withLock { s -> [CheckedContinuation<Void, Never>] in
            s.open = true
            let w = s.waiters
            s.waiters = []
            return w
        }
        for c in ws { c.resume() }
    }
}

/// Yields until `condition` holds or the attempts run out.
func eventually(_ attempts: Int = 2000, _ condition: () -> Bool) async -> Bool {
    for _ in 0..<attempts {
        if condition() { return true }
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(1))
    }
    return condition()
}
