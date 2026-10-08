import Foundation

/// Async client for the Lemon Squeezy licence API. No API key is needed: the three endpoints are public and the
/// docs' curl examples send only `Accept: application/json` and form fields.
///
/// - Activate: https://docs.lemonsqueezy.com/api/license-api/activate-license-key
/// - Validate: https://docs.lemonsqueezy.com/api/license-api/validate-license-key
/// - Deactivate: https://docs.lemonsqueezy.com/api/license-api/deactivate-license-key
///
/// The docs do not list status codes. In practice Lemon Squeezy answers 404 for an unknown key, 400 for a refused
/// activation (with the reason in `error`) and 422 for missing parameters; the client also copes with `200` bodies
/// that say `valid: false`.
public struct LicenseClient: Sendable {
    public struct Configuration: Sendable {
        public var baseURL: URL
        /// When set, keys whose `meta.store_id` differs are rejected (the docs recommend this check).
        public var expectedStoreID: Int?
        /// When set, keys whose `meta.product_id` differs are rejected.
        public var expectedProductID: Int?

        public init(
            baseURL: URL = URL(string: "https://api.lemonsqueezy.com")!,
            expectedStoreID: Int? = nil,
            expectedProductID: Int? = nil
        ) {
            self.baseURL = baseURL
            self.expectedStoreID = expectedStoreID
            self.expectedProductID = expectedProductID
        }
    }

    public let configuration: Configuration
    private let session: URLSession

    public init(configuration: Configuration = Configuration(), session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    // MARK: Endpoints

    /// Activates `key` for a new instance called `instanceName`.
    public func activate(key: LicenseKey, instanceName: String) async throws -> ActivationResponse {
        let response: ActivationResponse = try await post(
            "v1/licenses/activate",
            fields: [("license_key", key.apiValue), ("instance_name", instanceName)]
        )
        guard response.activated else { throw Self.failure(message: response.error, info: response.licenseKey) }
        if !matchesExpectations(response.meta) {
            // Free the seat we just used; the key belongs to someone else's product.
            if let id = response.instance?.id { _ = try? await deactivate(key: key, instanceID: id) }
            throw LicenseError.productMismatch
        }
        return response
    }

    /// Validates `key`, optionally for one instance.
    public func validate(key: LicenseKey, instanceID: String? = nil) async throws -> ValidationResponse {
        var fields = [("license_key", key.apiValue)]
        if let instanceID { fields.append(("instance_id", instanceID)) }
        let response: ValidationResponse = try await post("v1/licenses/validate", fields: fields)
        guard response.valid else { throw Self.failure(message: response.error, info: response.licenseKey) }
        if let status = response.licenseKey?.status, status == .disabled { throw LicenseError.keyDisabled }
        if !matchesExpectations(response.meta) { throw LicenseError.productMismatch }
        return response
    }

    /// Frees the activation held by `instanceID`.
    public func deactivate(key: LicenseKey, instanceID: String) async throws -> DeactivationResponse {
        let response: DeactivationResponse = try await post(
            "v1/licenses/deactivate",
            fields: [("license_key", key.apiValue), ("instance_id", instanceID)]
        )
        guard response.deactivated else { throw Self.failure(message: response.error, info: response.licenseKey) }
        return response
    }

    // MARK: Plumbing

    private func matchesExpectations(_ meta: LicenseMeta?) -> Bool {
        if let store = configuration.expectedStoreID, meta?.storeID != store { return false }
        if let product = configuration.expectedProductID, meta?.productID != product { return false }
        return true
    }

    private func post<R: Decodable & Sendable>(_ path: String, fields: [(String, String)]) async throws -> R {
        var request = URLRequest(url: configuration.baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncode(fields)

        let data: Data
        let http: HTTPURLResponse
        do {
            let (d, r) = try await session.data(for: request)
            guard let h = r as? HTTPURLResponse else { throw LicenseError.decoding }
            data = d
            http = h
        } catch let error as URLError {
            throw LicenseError.network(error.code)
        }

        guard (200..<300).contains(http.statusCode) else {
            throw Self.map(status: http.statusCode, retryAfter: http.value(forHTTPHeaderField: "Retry-After"), body: data)
        }
        do {
            return try Self.decoder.decode(R.self, from: data)
        } catch {
            throw LicenseError.decoding
        }
    }

    static func formEncode(_ fields: [(String, String)]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let body = fields.map { name, value in
            "\(name)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")"
        }.joined(separator: "&")
        return Data(body.utf8)
    }

    private struct ErrorBody: Decodable {
        let error: String?
        let licenseKey: LicenseKeyInfo?
        enum CodingKeys: String, CodingKey {
            case error
            case licenseKey = "license_key"
        }
    }

    static func map(status: Int, retryAfter: String?, body: Data) -> LicenseError {
        if status == 429 { return .rateLimited(retryAfter: retryAfter.flatMap { TimeInterval($0.trimmingCharacters(in: .whitespaces)) }) }
        if status >= 500 { return .server(status) }
        if status == 404 { return .invalidKey }
        let parsed = try? decoder.decode(ErrorBody.self, from: body)
        let error = failure(message: parsed?.error, info: parsed?.licenseKey)
        if case .invalidKey = error, status == 400 || status == 422 || status == 403 {
            return .badRequest(parsed?.error ?? "Request refused (\(status)).")
        }
        return error
    }

    /// Turns an error message and licence status into the most specific error.
    static func failure(message: String?, info: LicenseKeyInfo?) -> LicenseError {
        if let status = info?.status {
            if status == .disabled { return .keyDisabled }
            if status == .expired { return .keyExpired }
        }
        let text = message?.lowercased() ?? ""
        if text.contains("activation limit") { return .activationLimitReached }
        if let info, let limit = info.activationLimit, info.activationUsage >= limit, text.isEmpty { return .activationLimitReached }
        return .invalidKey
    }

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = f.date(from: raw) { return date }
            f.formatOptions = [.withInternetDateTime]
            if let date = f.date(from: raw) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Bad date \(raw)"))
        }
        return d
    }()
}
