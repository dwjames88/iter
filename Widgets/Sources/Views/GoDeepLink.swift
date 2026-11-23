import Foundation

/// The URLs the Live Activity and the widget open. The `iter` scheme is registered in iOS/Info.plist (CFBundleURLTypes); the shell
/// routes them:
///
///   iter://go                          open the Go screen
///   iter://go/navigate                 open Go and start navigation to the next stop
///   iter://go/navigate?stop=<uuid>     the same for one named stop (the widget knows the stop; the Live Activity's content does not)
enum GoDeepLink {
    static let go = URL(string: "iter://go")!

    static func navigate(stop: UUID? = nil) -> URL {
        var c = URLComponents()
        c.scheme = "iter"
        c.host = "go"
        c.path = "/navigate"
        if let stop { c.queryItems = [URLQueryItem(name: "stop", value: stop.uuidString)] }
        return c.url ?? go
    }
}
