import Foundation

/// Builds its value on first read and keeps it. Held in `@State`, it gives a view a model that is made once for the view's
/// identity, without constructing a throw-away one every time the parent's body runs.
@MainActor
final class Lazy<Value> {
    private var make: (@MainActor () -> Value)?
    private var stored: Value?

    init(_ make: @escaping @MainActor () -> Value) { self.make = make }

    var value: Value {
        if let stored { return stored }
        let made = make!()
        stored = made
        make = nil
        return made
    }
}
