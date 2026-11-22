import Foundation
import Synchronization
import IterCore
@testable import IterServices

/// Loads a fixture from `Fixtures/`. Most are DOCUMENTED-SCHEMA fixtures; the `-live-` OpenWeather ones are recorded real responses (see Fixtures/README.md).
enum WeatherFixture {
    static func data(_ name: String) -> Data {
        let url = Bundle.module.resourceURL!.appendingPathComponent("Fixtures").appendingPathComponent(name)
        return try! Data(contentsOf: url)
    }
    static func json(_ name: String) -> [String: Any] {
        try! JSONSerialization.jsonObject(with: data(name)) as! [String: Any]
    }
    static func encode(_ object: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: object)
    }
}

/// A clock tests can move.
final class TestClock: Sendable {
    private let t: Mutex<Date>
    init(_ start: Date = Date(timeIntervalSince1970: 1_595_246_400 + 600)) { t = Mutex(start) }   // 2020-07-20 12:10 UTC
    var now: Date { t.withLock { $0 } }
    func advance(_ s: TimeInterval) { t.withLock { $0 = $0.addingTimeInterval(s) } }
    func set(_ d: Date) { t.withLock { $0 = d } }
}

/// A transport that answers from a script and records every request. Never touches the network.
final class FakeTransport: HTTPTransport {
    typealias Reply = @Sendable (URLRequest) throws -> (status: Int, body: Data)
    private let state = Mutex<(requests: [URLRequest], reply: Reply)>(([], { _ in (200, Data()) }))

    init(_ reply: @escaping Reply = { _ in (200, Data()) }) { state.withLock { $0.reply = reply } }

    func setReply(_ reply: @escaping Reply) { state.withLock { $0.reply = reply } }
    var requests: [URLRequest] { state.withLock { $0.requests } }
    var callCount: Int { requests.count }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let reply = state.withLock { s -> Reply in s.requests.append(request); return s.reply }
        let (status, body) = try reply(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        return (body, response)
    }
}

func requestBody(_ r: URLRequest) -> [String: Any] {
    (try? JSONSerialization.jsonObject(with: r.httpBody ?? Data())) as? [String: Any] ?? [:]
}

/// Defaults that vanish with the test.
func scratchDefaults() -> UserDefaults {
    let name = "iter.tests." + UUID().uuidString
    let d = UserDefaults(suiteName: name)!
    d.removePersistentDomain(forName: name)
    return d
}

func scratchDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("iter-tests-" + UUID().uuidString, isDirectory: true)
}

let moabSpot = Coordinate(latitude: 38.5733, longitude: -109.5498)
let alpsSpot = Coordinate(latitude: 46.5, longitude: 8.0)
let hawaiiSpot = Coordinate(latitude: 19.82, longitude: -155.47)
let secretKey = "SECRETKEY0123456789abcdef"

func resolver(_ keys: [ForecastSource: String] = [.openWeather: secretKey, .windy: secretKey]) -> APIKeyResolver {
    APIKeyResolver(store: InMemoryAPIKeyStore(keys), environment: { [:] }, launchArgument: { _ in nil })
}

/// Everything an OpenWeather or Windy service needs, with a fake wire.
struct Rig {
    let transport: FakeTransport
    let clock: TestClock
    let defaults: UserDefaults
    let budget: CallBudget
    let directory: URL?

    init(transport: FakeTransport = FakeTransport(), clock: TestClock = TestClock(), directory: URL? = nil, caps: [ForecastSource: Int] = CallBudget.defaultCaps) {
        self.transport = transport
        self.clock = clock
        self.defaults = scratchDefaults()
        self.directory = directory
        let c = clock
        self.budget = CallBudget(defaults: defaults, caps: caps, now: { c.now })
    }

    func openWeather(keys: APIKeyResolver = resolver(), cache: ProviderCache? = nil) -> OpenWeatherService {
        let c = clock
        return OpenWeatherService(keys: keys, transport: transport,
                                  cache: cache ?? ProviderCache(directory: directory, validity: .throughNextClockHour, now: { c.now }),
                                  budget: budget, now: { c.now })
    }

    func windy(keys: APIKeyResolver = resolver(), keyType: WindyKeyType = .professional, mode: WindyModelMode = .bestForSpot,
               cache: ProviderCache? = nil) -> WindyService {
        let c = clock
        return WindyService(keys: keys, transport: transport,
                            cache: cache ?? ProviderCache(directory: nil, validity: .interval(3 * 3600), now: { c.now }),
                            budget: budget, keyType: keyType, modelMode: mode, now: { c.now })
    }
}

/// A provider that answers or fails on demand.
final class StubProvider: WeatherProviding {
    let source: ForecastSource
    private let result: Mutex<Result<Date, WeatherError>>
    private let calls = Mutex(0)
    init(_ source: ForecastSource, _ result: Result<Date, WeatherError>) {
        self.source = source
        self.result = Mutex(result)
    }
    var callCount: Int { calls.withLock { $0 } }
    func forecast(for coordinate: Coordinate) async throws -> Forecast {
        calls.withLock { $0 += 1 }
        switch result.withLock({ $0 }) {
        case .success(let date): return Forecast(coordinate: coordinate, hours: [], days: [], fetchedAt: date, source: source)
        case .failure(let e): throw e
        }
    }
    func attribution() async -> WeatherAttributionInfo? {
        WeatherAttributionInfo(serviceName: source.rawValue, legalPageURL: URL(string: "https://example.com")!)
    }
}
