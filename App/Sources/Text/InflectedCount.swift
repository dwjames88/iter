import Foundation
import Synchronization

/// Inflected count strings ("3 stops"), built once per (format, count, locale). Automatic grammar agreement
/// (`^[3 stop](inflect: true)`) is expensive, and lists and strips ask for the same few counts on every body pass.
///
/// The localized literal stays at the call site, inside the `make` closure, so string-catalog extraction sees it exactly as
/// before; `make` runs only on a miss. `key` names the format (use the literal's own text, e.g. "stop") and must be
/// the same for every call site that builds the same string.
enum InflectedCount {
    private struct Key: Hashable {
        var format: String
        var count: Int
        var locale: String
    }

    private static let cache = Mutex<[Key: String]>([:])

    static func string(_ format: String, count: Int, make: () -> AttributedString) -> String {
        let key = Key(format: format, count: count, locale: Locale.current.identifier)
        if let hit = cache.withLock({ $0[key] }) { return hit }
        let made = String(make().characters)
        cache.withLock { cache in
            if cache.count > 500 { cache.removeAll(keepingCapacity: true) }
            cache[key] = made
        }
        return made
    }
}
