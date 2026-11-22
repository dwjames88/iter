import Foundation
@testable import IterLicensing

/// A URLProtocol fake. Each test registers a handler under a unique id that travels in a request header, so tests
/// can run in parallel without sharing a static handler.
final class FakeURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest, Data) throws -> (Int, [String: String], Data)

    nonisolated(unsafe) private static var handlers: [String: Handler] = [:]
    private static let lock = NSLock()
    static let header = "X-Fake-Test-ID"

    static func register(_ handler: @escaping Handler) -> String {
        let id = UUID().uuidString
        lock.withLock { handlers[id] = handler }
        return id
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let id = request.value(forHTTPHeaderField: Self.header) ?? ""
        guard let handler = Self.lock.withLock({ Self.handlers[id] }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        var body = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open()
            var buf = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let n = stream.read(&buf, maxLength: buf.count)
                if n <= 0 { break }
                body.append(contentsOf: buf[0..<n])
            }
            stream.close()
        }
        do {
            let (status, headers, data) = try handler(request, body)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

/// Collects what the fake server saw.
final class Recorder: @unchecked Sendable {
    struct Call: Sendable { let path: String; let method: String; let accept: String?; let contentType: String?; let body: String }
    private let lock = NSLock()
    private var _calls: [Call] = []
    var calls: [Call] { lock.withLock { _calls } }
    func add(_ request: URLRequest, _ body: Data) {
        lock.withLock {
            _calls.append(Call(
                path: request.url?.path() ?? "", method: request.httpMethod ?? "",
                accept: request.value(forHTTPHeaderField: "Accept"),
                contentType: request.value(forHTTPHeaderField: "Content-Type"),
                body: String(decoding: body, as: UTF8.self)))
        }
    }
}

func makeSession(_ handler: @escaping FakeURLProtocol.Handler) -> URLSession {
    let id = FakeURLProtocol.register(handler)
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [FakeURLProtocol.self]
    config.httpAdditionalHeaders = [FakeURLProtocol.header: id]
    return URLSession(configuration: config)
}

/// Session that records every call and answers each with `respond(path)`.
func makeSession(recorder: Recorder, respond: @escaping @Sendable (String) -> (Int, [String: String], Data)) -> URLSession {
    makeSession { request, body in
        recorder.add(request, body)
        return respond(request.url?.path() ?? "")
    }
}

/// Mutable clock for the manager.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date
    init(_ date: Date) { self.date = date }
    var now: Date { lock.withLock { date } }
    func advance(days: Double) { lock.withLock { date = date.addingTimeInterval(days * 86_400) } }
    func set(_ d: Date) { lock.withLock { date = d } }
}

// Example payloads from https://docs.lemonsqueezy.com/api/license-api/ (activate, validate, deactivate).
enum Fixtures {
    static let key = "38b1460a-5104-4067-a91d-77b872934d51"

    static let activateOK = Data("""
    {"activated": true, "error": null,
     "license_key": {"id": 1, "status": "active", "key": "38b1460a-5104-4067-a91d-77b872934d51", "activation_limit": 1, "activation_usage": 5, "created_at": "2021-01-24T14:15:07.000000Z", "expires_at": null},
     "instance": {"id": "47596ad9-a811-4ebf-ac8a-03fc7b6d2a17", "name": "Test", "created_at": "2021-04-06T14:15:07.000000Z"},
     "meta": {"store_id": 1, "order_id": 2, "order_item_id": 3, "product_id": 4, "product_name": "Example Product", "variant_id": 5, "variant_name": "Default", "customer_id": 6, "customer_name": "John Doe", "customer_email": "john@example.com"}}
    """.utf8)

    static let activateLimit = Data("""
    {"activated": false, "error": "This license key has reached the activation limit.",
     "license_key": {"id": 1, "status": "active", "key": "38b1460a-5104-4067-a91d-77b872934d51", "activation_limit": 5, "activation_usage": 5, "created_at": "2021-01-24T14:15:07.000000Z", "expires_at": null},
     "meta": {"store_id": 1, "order_id": 2, "order_item_id": 3, "product_id": 4, "product_name": "Lemonade", "variant_id": 5, "variant_name": "Default", "customer_id": 6, "customer_name": "John Doe", "customer_email": "john@example.com"}}
    """.utf8)

    static let validateOK = Data("""
    {"valid": true, "error": null,
     "license_key": {"id": 1, "status": "active", "key": "38b1460a-5104-4067-a91d-77b872934d51", "activation_limit": 1, "activation_usage": 5, "created_at": "2021-01-24T14:15:07.000000Z", "expires_at": "2022-01-24T14:15:07.000000Z"},
     "instance": {"id": "f90ec370-fd83-46a5-8bbd-44a241e78665", "name": "Test", "created_at": "2021-02-24T14:15:07.000000Z"},
     "meta": {"store_id": 1, "order_id": 2, "product_id": 4, "product_name": "Lemonade", "customer_id": 6, "customer_name": "John Doe", "customer_email": "john@example.com"}}
    """.utf8)

    static let validateDisabled = Data("""
    {"valid": false, "error": "license_key is disabled.",
     "license_key": {"id": 1, "status": "disabled", "key": "38b1460a-5104-4067-a91d-77b872934d51", "activation_limit": 1, "activation_usage": 1, "created_at": "2021-01-24T14:15:07.000000Z", "expires_at": null},
     "instance": null,
     "meta": {"store_id": 1, "order_id": 2, "product_id": 4, "product_name": "Lemonade", "customer_id": 6, "customer_name": "John Doe", "customer_email": "john@example.com"}}
    """.utf8)

    static let notFound = Data(#"{"valid": false, "error": "license_key not found.", "license_key": null, "instance": null, "meta": null}"#.utf8)

    static let deactivateOK = Data("""
    {"deactivated": true, "error": null,
     "license_key": {"id": 1, "status": "inactive", "key": "38b1460a-5104-4067-a91d-77b872934d51", "activation_limit": 5, "activation_usage": 0, "created_at": "2021-01-24T14:15:07.000000Z", "expires_at": null},
     "meta": {"store_id": 1, "order_id": 2, "order_item_id": 3, "product_id": 4, "product_name": "Lemonade", "variant_id": 5, "variant_name": "Citrus Burst", "customer_id": 6, "customer_name": "John Doe", "customer_email": "john@example.com"}}
    """.utf8)

    static let unprocessable = Data(#"{"message": "The license_key field is required."}"#.utf8)
}
