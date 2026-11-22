import Testing
import Foundation
@testable import IterLicensing

@Suite("LicenseClient")
struct LicenseClientTests {
    let key = LicenseKey(parsing: Fixtures.key)!

    func client(
        store: Int? = nil, product: Int? = nil, recorder: Recorder = Recorder(),
        respond: @escaping @Sendable (String) -> (Int, [String: String], Data)
    ) -> LicenseClient {
        LicenseClient(
            configuration: .init(baseURL: URL(string: "https://example.test")!, expectedStoreID: store, expectedProductID: product),
            session: makeSession(recorder: recorder, respond: respond))
    }

    func fixed(_ status: Int, _ data: Data, headers: [String: String] = [:]) -> @Sendable (String) -> (Int, [String: String], Data) {
        { _ in (status, headers, data) }
    }

    @Test func activateDecodesDocExample() async throws {
        let r = try await client(respond: fixed(200, Fixtures.activateOK)).activate(key: key, instanceName: "Test")
        #expect(r.activated)
        #expect(r.instance?.id == "47596ad9-a811-4ebf-ac8a-03fc7b6d2a17")
        #expect(r.licenseKey?.status == .active)
        #expect(r.licenseKey?.activationLimit == 1)
        #expect(r.licenseKey?.expiresAt == nil)
        #expect(r.licenseKey?.createdAt == Date(timeIntervalSince1970: 1_611_497_707))
        #expect(r.meta?.storeID == 1)
        #expect(r.meta?.productID == 4)
        #expect(r.meta?.customerEmail == "john@example.com")
    }

    @Test func validateDecodesDocExample() async throws {
        let r = try await client(respond: fixed(200, Fixtures.validateOK)).validate(key: key, instanceID: "f90ec370-fd83-46a5-8bbd-44a241e78665")
        #expect(r.valid)
        #expect(r.licenseKey?.expiresAt != nil)
        #expect(r.instance?.name == "Test")
    }

    @Test func deactivateDecodesDocExample() async throws {
        let r = try await client(respond: fixed(200, Fixtures.deactivateOK)).deactivate(key: key, instanceID: "x")
        #expect(r.deactivated)
        #expect(r.licenseKey?.status == .inactive)
        #expect(r.licenseKey?.activationUsage == 0)
    }

    @Test func requestEncoding() async throws {
        let rec = Recorder()
        let c = client(recorder: rec, respond: fixed(200, Fixtures.activateOK))
        _ = try await c.activate(key: key, instanceName: "MacBook Pro – Dan & Co")
        _ = try? await c.validate(key: key, instanceID: "abc 123")
        let calls = rec.calls
        #expect(calls.count == 2)
        #expect(calls[0].path == "/v1/licenses/activate")
        #expect(calls[0].method == "POST")
        #expect(calls[0].accept == "application/json")
        #expect(calls[0].contentType == "application/x-www-form-urlencoded")
        #expect(calls[0].body == "license_key=38b1460a-5104-4067-a91d-77b872934d51&instance_name=MacBook%20Pro%20%E2%80%93%20Dan%20%26%20Co")
        #expect(calls[1].path == "/v1/licenses/validate")
        #expect(calls[1].body == "license_key=38b1460a-5104-4067-a91d-77b872934d51&instance_id=abc%20123")
    }

    @Test func deactivateRequestPath() async throws {
        let rec = Recorder()
        _ = try await client(recorder: rec, respond: fixed(200, Fixtures.deactivateOK)).deactivate(key: key, instanceID: "i1")
        #expect(rec.calls.first?.path == "/v1/licenses/deactivate")
        #expect(rec.calls.first?.body == "license_key=38b1460a-5104-4067-a91d-77b872934d51&instance_id=i1")
    }

    @Test func activationLimitReached() async {
        await #expect(throws: LicenseError.activationLimitReached) {
            try await client(respond: fixed(400, Fixtures.activateLimit)).activate(key: key, instanceName: "x")
        }
    }

    @Test func notFoundIsInvalidKey() async {
        await #expect(throws: LicenseError.invalidKey) {
            try await client(respond: fixed(404, Fixtures.notFound)).validate(key: key)
        }
    }

    @Test func validFalseOn200IsInvalidKey() async {
        await #expect(throws: LicenseError.invalidKey) {
            try await client(respond: fixed(200, Fixtures.notFound)).validate(key: key)
        }
    }

    @Test func disabledKeyIsReported() async {
        await #expect(throws: LicenseError.keyDisabled) {
            try await client(respond: fixed(400, Fixtures.validateDisabled)).validate(key: key)
        }
    }

    @Test func badRequest400() async {
        let body = Data(#"{"activated": false, "error": "Something odd happened."}"#.utf8)
        await #expect(throws: LicenseError.badRequest("Something odd happened.")) {
            try await client(respond: fixed(400, body)).activate(key: key, instanceName: "x")
        }
    }

    @Test func unprocessable422() async {
        let body = Data(#"{"error": "The license_key field is required."}"#.utf8)
        await #expect(throws: LicenseError.badRequest("The license_key field is required.")) {
            try await client(respond: fixed(422, body)).activate(key: key, instanceName: "x")
        }
    }

    @Test func rateLimitedCarriesRetryAfter() async {
        await #expect(throws: LicenseError.rateLimited(retryAfter: 30)) {
            try await client(respond: fixed(429, Data(), headers: ["Retry-After": "30"])).validate(key: key)
        }
        await #expect(throws: LicenseError.rateLimited(retryAfter: nil)) {
            try await client(respond: fixed(429, Data())).validate(key: key)
        }
    }

    @Test func serverError() async {
        await #expect(throws: LicenseError.server(503)) {
            try await client(respond: fixed(503, Data("<html>".utf8))).validate(key: key)
        }
    }

    @Test func garbageBodyIsDecodingError() async {
        await #expect(throws: LicenseError.decoding) {
            try await client(respond: fixed(200, Data("nope".utf8))).validate(key: key)
        }
    }

    @Test func networkDown() async {
        let session = makeSession { _, _ in throw URLError(.notConnectedToInternet) }
        let c = LicenseClient(configuration: .init(baseURL: URL(string: "https://example.test")!), session: session)
        await #expect(throws: LicenseError.network(.notConnectedToInternet)) {
            try await c.validate(key: key)
        }
    }

    @Test func storeMismatchRejected() async {
        await #expect(throws: LicenseError.productMismatch) {
            try await client(store: 99, respond: fixed(200, Fixtures.validateOK)).validate(key: key)
        }
    }

    @Test func productMismatchOnActivateFreesTheSeat() async {
        let rec = Recorder()
        let c = client(product: 99, recorder: rec) { path in
            path.hasSuffix("activate") && !path.hasSuffix("deactivate") ? (200, [:], Fixtures.activateOK) : (200, [:], Fixtures.deactivateOK)
        }
        await #expect(throws: LicenseError.productMismatch) { try await c.activate(key: key, instanceName: "x") }
        #expect(rec.calls.map(\.path) == ["/v1/licenses/activate", "/v1/licenses/deactivate"])
    }

    @Test func matchingStoreAndProductAccepted() async throws {
        let r = try await client(store: 1, product: 4, respond: fixed(200, Fixtures.validateOK)).validate(key: key)
        #expect(r.valid)
    }
}
