import Foundation

/// A licence key as typed or pasted by the user, normalised.
///
/// Lemon Squeezy generates keys in the UUID shape (`38b1460a-5104-4067-a91d-77b872934d51`, see the example payloads at
/// https://docs.lemonsqueezy.com/api/license-api/activate-license-key). Store owners can also configure custom key
/// formats, so the 4 x 8 shape (`XXXXXXXX-XXXXXXXX-XXXXXXXX-XXXXXXXX`) is accepted too. Input is trimmed, upper-cased and
/// stripped of spaces, newlines and stray dashes. A dash-less 32 character string is read as the UUID shape.
public struct LicenseKey: Sendable, Hashable, CustomStringConvertible {
    /// Canonical upper-case form, with dashes.
    public let value: String

    /// The string sent to the API. The docs show lower-case keys, so the wire form is lower-case.
    public var apiValue: String { value.lowercased() }

    /// Display form that hides everything except the last four characters, e.g. `••••••••-••••-••••-••••-••••••••D51`.
    public var masked: String {
        let head = value.dropLast(4).map { $0 == "-" ? "-" : "\u{2022}" }.joined()
        return head + value.suffix(4)
    }

    public var description: String { masked }

    public init?(parsing input: String) {
        let hexSet = Set("0123456789ABCDEF")
        let upper = input.uppercased()

        // Keep the dash layout if the user typed 4 groups of 8; otherwise ignore dashes entirely.
        let groups = upper.split(whereSeparator: { $0 == "-" }).map { $0.filter { !$0.isWhitespace } }
        if groups.count == 4, groups.allSatisfy({ $0.count == 8 }), groups.allSatisfy({ $0.allSatisfy(hexSet.contains) }) {
            self.value = groups.joined(separator: "-")
            return
        }

        let compact = upper.filter { !$0.isWhitespace && $0 != "-" }
        guard compact.count == 32, compact.allSatisfy(hexSet.contains) else { return nil }
        let c = Array(compact)
        func slice(_ r: Range<Int>) -> String { String(c[r]) }
        self.value = [slice(0..<8), slice(8..<12), slice(12..<16), slice(16..<20), slice(20..<32)].joined(separator: "-")
    }
}
