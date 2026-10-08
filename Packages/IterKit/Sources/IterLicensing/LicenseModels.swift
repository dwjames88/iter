import Foundation

/// Status of a licence key as reported by Lemon Squeezy: `inactive`, `active`, `expired` or `disabled`.
/// https://docs.lemonsqueezy.com/api/license-keys
public enum LicenseKeyStatus: Sendable, Equatable, Codable {
    case inactive, active, expired, disabled
    case other(String)

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = switch raw {
        case "inactive": .inactive
        case "active": .active
        case "expired": .expired
        case "disabled": .disabled
        default: .other(raw)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }

    public var rawValue: String {
        switch self {
        case .inactive: "inactive"
        case .active: "active"
        case .expired: "expired"
        case .disabled: "disabled"
        case .other(let s): s
        }
    }
}

/// The `license_key` object in every licence API response.
public struct LicenseKeyInfo: Sendable, Equatable, Codable {
    public let id: Int
    public let status: LicenseKeyStatus
    public let key: String
    /// `nil` means unlimited activations.
    public let activationLimit: Int?
    public let activationUsage: Int
    public let createdAt: Date?
    public let expiresAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, status, key
        case activationLimit = "activation_limit"
        case activationUsage = "activation_usage"
        case createdAt = "created_at"
        case expiresAt = "expires_at"
    }
}

/// The `instance` object returned by activate (and by validate when `instance_id` was sent).
public struct LicenseInstance: Sendable, Equatable, Codable {
    public let id: String
    public let name: String
    public let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name
        case createdAt = "created_at"
    }
}

/// The `meta` object: store, order, product and customer details.
public struct LicenseMeta: Sendable, Equatable, Codable {
    public let storeID: Int
    public let orderID: Int?
    public let orderItemID: Int?
    public let productID: Int
    public let productName: String?
    public let variantID: Int?
    public let variantName: String?
    public let customerID: Int?
    public let customerName: String?
    public let customerEmail: String?

    enum CodingKeys: String, CodingKey {
        case storeID = "store_id"
        case orderID = "order_id"
        case orderItemID = "order_item_id"
        case productID = "product_id"
        case productName = "product_name"
        case variantID = "variant_id"
        case variantName = "variant_name"
        case customerID = "customer_id"
        case customerName = "customer_name"
        case customerEmail = "customer_email"
    }
}

/// Response of `POST /v1/licenses/activate`.
public struct ActivationResponse: Sendable, Equatable, Codable {
    public let activated: Bool
    public let error: String?
    public let licenseKey: LicenseKeyInfo?
    public let instance: LicenseInstance?
    public let meta: LicenseMeta?

    enum CodingKeys: String, CodingKey {
        case activated, error, instance, meta
        case licenseKey = "license_key"
    }
}

/// Response of `POST /v1/licenses/validate`.
public struct ValidationResponse: Sendable, Equatable, Codable {
    public let valid: Bool
    public let error: String?
    public let licenseKey: LicenseKeyInfo?
    public let instance: LicenseInstance?
    public let meta: LicenseMeta?

    enum CodingKeys: String, CodingKey {
        case valid, error, instance, meta
        case licenseKey = "license_key"
    }
}

/// Response of `POST /v1/licenses/deactivate`.
public struct DeactivationResponse: Sendable, Equatable, Codable {
    public let deactivated: Bool
    public let error: String?
    public let licenseKey: LicenseKeyInfo?
    public let meta: LicenseMeta?

    enum CodingKeys: String, CodingKey {
        case deactivated, error, meta
        case licenseKey = "license_key"
    }
}

public enum LicenseError: Error, Sendable, Equatable {
    /// The input is not shaped like a licence key.
    case malformedKey
    /// 404, or `valid: false` / `activated: false` for an unknown key or instance.
    case invalidKey
    case keyDisabled
    case keyExpired
    case activationLimitReached
    case rateLimited(retryAfter: TimeInterval?)
    /// 400 or 422 with the server's message.
    case badRequest(String)
    case network(URLError.Code)
    case server(Int)
    case decoding
    /// The key is real but belongs to another store or product.
    case productMismatch
}
