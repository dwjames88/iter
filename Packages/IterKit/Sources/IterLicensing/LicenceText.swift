import Foundation

/// Where the licence settings send people, and the store identifiers the client checks.
public enum LicenceSetup {
    /// The site's origin. It follows the site's `SITE_ORIGIN` setting (wrangler.jsonc in the site repository).
    public static let siteOrigin = URL(string: "https://iter.example")!

    /// "Where's my key?" opens this page on the site.
    public static let activateURL = siteOrigin.appending(path: "activate")

    /// The client configuration the app uses. Put the Lemon Squeezy `store_id` and `product_id` here once the store
    /// exists; until then any key is accepted by the client and the server alone decides.
    public static let clientConfiguration = LicenseClient.Configuration(expectedStoreID: nil, expectedProductID: nil)
}

/// The words the licence settings show. Plain English; the platform panes add layout, not copy.
public enum LicenceText {
    /// A short sentence for a failed action. Never shows a raw error type.
    public static func message(for error: LicenseError) -> String {
        switch error {
        case .malformedKey:
            "That doesn't look like a licence key. Copy it again from your email."
        case .invalidKey:
            "That key wasn't found. Check it against your email or your Lemon Squeezy order page."
        case .keyDisabled:
            "This key has been turned off, usually because the order was refunded."
        case .keyExpired:
            "This key has expired."
        case .activationLimitReached:
            "This key is already on its limit of Macs. Open Settings ▸ Licence on one you no longer use and choose Deactivate This Mac, then try again."
        case .rateLimited(let retryAfter):
            if let retryAfter, retryAfter >= 1 {
                "Too many tries in a short time. Wait \(Int(retryAfter.rounded(.up))) seconds and try again."
            } else {
                "Too many tries in a short time. Wait a minute and try again."
            }
        case .badRequest(let detail):
            detail.isEmpty ? "The licence server refused the request." : "The licence server said: \(detail)"
        case .network:
            "Iter couldn't reach the licence server. Check your connection and try again."
        case .server:
            "The licence server had a problem. Try again in a little while."
        case .decoding:
            "The licence server's answer wasn't what Iter expected. Try again in a little while."
        case .productMismatch:
            "That key is for a different product."
        }
    }

    /// A short sentence for any thrown error.
    public static func message(for error: any Error) -> String {
        if let error = error as? LicenseError { return message(for: error) }
        return "Iter couldn't read or save the licence in the Keychain."
    }

    /// One line for the status row.
    public static func statusTitle(_ state: LicenseState) -> String {
        switch state {
        case .unlicensed: "Not licensed"
        case .trial(let days): days == 1 ? "Trial, 1 day left" : "Trial, \(days) days left"
        case .licensed: "Licensed"
        case .expired: "Needs a check"
        case .revoked: "Key no longer valid"
        }
    }

    /// Plain explanation under the status, or nil when the title says enough.
    public static func statusDetail(_ state: LicenseState) -> String? {
        switch state {
        case .unlicensed, .trial:
            nil
        case .licensed(let email, _):
            email.map { "Licensed to \($0)." }
        case .expired:
            "Iter hasn't been able to confirm this licence for a while. Choose Check Now while you're online."
        case .revoked:
            "This key was turned off, usually because the order was refunded. Enter a different key to use a licence again."
        }
    }

    /// "12 Mar 2027", or the empty string for nil.
    public static func dateText(_ date: Date?) -> String {
        guard let date else { return "" }
        return date.formatted(.dateTime.day().month(.abbreviated).year())
    }
}
