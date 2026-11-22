import Foundation
import Synchronization

/// Inflected count strings ("3 stops"), built once per (format, count, locale). Automatic grammar agreement
/// (`^[3 stop](inflect: true)`) is expensive, and lists and strips ask for the same few counts on every body pass.
///
/// The localized literal stays at the call site, inside the `make` closure, so string-catalog extraction sees it;
/// `make` runs only on a miss. `key` names the format (use the literal's own text, e.g. "stop") and must be the same for
/// every call site that builds the same string. In this package build the literal with `bundle: .module`.
public enum InflectedCount {
    private struct Key: Hashable {
        var format: String
        var count: Int
        var locale: String
    }

    private static let cache = Mutex<[Key: String]>([:])

    public static func string(_ format: String, count: Int, locale: Locale = .current,
                              make: () -> AttributedString) -> String {
        let key = Key(format: format, count: count, locale: locale.identifier)
        if let hit = cache.withLock({ $0[key] }) { return hit }
        let made = String(make().characters)
        cache.withLock { cache in
            if cache.count > 500 { cache.removeAll(keepingCapacity: true) }
            cache[key] = made
        }
        return made
    }

    // The counts the UI kit itself needs. Each builds its literal here so extraction sees them.

    /// "3 stops"
    public static func stops(_ count: Int, locale: Locale = .current) -> String {
        string("stop", count: count, locale: locale) {
            AttributedString(localized: "^[\(count) stop](inflect: true)", bundle: .module, locale: locale,
                             comment: "Number of stops, e.g. 3 stops")
        }
    }

    /// "2 days"
    public static func days(_ count: Int, locale: Locale = .current) -> String {
        string("day", count: count, locale: locale) {
            AttributedString(localized: "^[\(count) day](inflect: true)", bundle: .module, locale: locale,
                             comment: "Number of days, e.g. 3 days")
        }
    }

    /// "4 places"
    public static func places(_ count: Int, locale: Locale = .current) -> String {
        string("place", count: count, locale: locale) {
            AttributedString(localized: "^[\(count) place](inflect: true)", bundle: .module, locale: locale,
                             comment: "Number of places, e.g. 4 places")
        }
    }

    /// "2 trips"
    public static func trips(_ count: Int, locale: Locale = .current) -> String {
        string("trip", count: count, locale: locale) {
            AttributedString(localized: "^[\(count) trip](inflect: true)", bundle: .module, locale: locale,
                             comment: "Number of trips, e.g. 2 trips")
        }
    }
}
