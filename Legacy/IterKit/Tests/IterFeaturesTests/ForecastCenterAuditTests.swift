import Foundation
import Synchronization
import Testing
import IterCore
import IterServices
@testable import IterFeatures

/// A provider whose fetches wait at a gate until the test lets them go, and which counts its calls.
private final class GatedWeather: WeatherProviding {
    private struct State {
        var waiting: [(key: String, go: CheckedContinuation<Void, Never>)] = []
        var calls: [String] = []
        var failure: WeatherError?
        var cancel = false
    }
    private let state = Mutex(State())
    let gated: Bool
    var source: ForecastSource { .openWeather }
    init(gated: Bool = true) { self.gated = gated }

    var calls: [String] { state.withLock { $0.calls } }
    var waitingCount: Int { state.withLock { $0.waiting.count } }
    func fail(with error: WeatherError?) { state.withLock { $0.failure = error } }
    func throwCancellation(_ on: Bool) { state.withLock { $0.cancel = on } }

    func releaseAll() {
        let waiting = state.withLock { s -> [CheckedContinuation<Void, Never>] in
            defer { s.waiting = [] }
            return s.waiting.map(\.go)
        }
        waiting.forEach { $0.resume() }
    }

    func forecast(for coordinate: Coordinate) async throws -> Forecast {
        state.withLock { $0.calls.append(coordinate.cacheKey) }
        if gated { await withCheckedContinuation { c in state.withLock { $0.waiting.append((coordinate.cacheKey, c)) } } }
        if state.withLock({ $0.cancel }) { throw CancellationError() }
        if let error = state.withLock({ $0.failure }) { throw error }
        return Forecast(coordinate: coordinate, hours: [], days: [], fetchedAt: Date(timeIntervalSince1970: 1_790_000_000), source: .openWeather)
    }
    func attribution() async -> WeatherAttributionInfo? { nil }
}

private func spots(_ n: Int) -> [Coordinate] { (0..<n).map { Coordinate(latitude: 38.0 + Double($0) * 0.05, longitude: -109.5) } }

@MainActor private func waitUntil(_ what: String = "", timeout: Duration = .seconds(5), _ done: () -> Bool) async {
    let deadline = ContinuousClock.now + timeout
    while !done(), ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(2)) }
    #expect(done(), "timed out: \(what)")
}

@MainActor
@Suite struct ForecastCenterAuditTests {
    @Test func aBatchOfFetchesBumpsTheRevisionOnce() async {
        let provider = GatedWeather()
        // A long window: only the last fetch landing can show the batch, so the count does not depend on timing.
        let center = ForecastCenter(provider: provider, coalescing: .seconds(30))
        let batch = spots(24)
        center.requestAll(batch)
        await waitUntil("all fetches reached the provider") { provider.waitingCount == 24 }
        let before = center.revision
        provider.releaseAll()
        await waitUntil("all states loaded") { batch.allSatisfy { center.state(for: $0).forecast != nil } }
        #expect(center.revision - before == 1)
        #expect(center.status == .ok)
    }

    @Test func aSlowStragglerDoesNotHoldBackTheBatchPastTheWindow() async {
        let provider = GatedWeather(gated: false)
        let center = ForecastCenter(provider: provider, coalescing: .milliseconds(10))
        let batch = spots(10)
        center.requestAll(batch)
        await waitUntil("all states loaded") { batch.allSatisfy { center.state(for: $0).forecast != nil } }
        #expect(center.revision <= 3)       // was one per fetch (10)
    }

    @Test func aLoneRequestIsShownTheMomentItLands() async {
        let provider = GatedWeather()
        let center = ForecastCenter(provider: provider, coalescing: .seconds(30))
        let c = spots(1)[0]
        center.request(c)
        await waitUntil { provider.waitingCount == 1 }
        provider.releaseAll()
        await waitUntil("shown without waiting for the window") { center.state(for: c).forecast != nil }
        #expect(center.revision == 1)
    }

    @Test func aResultIdenticalToWhatIsShownDoesNotBump() async {
        let provider = GatedWeather(gated: false)
        let center = ForecastCenter(provider: provider)
        let c = spots(1)[0]
        _ = await center.load(c)
        let after = center.revision
        _ = await center.refresh(c)
        _ = await center.refresh(c)
        #expect(center.revision == after)
        #expect(provider.calls.count == 3)
    }

    @Test func aFailureThatChangesNothingOnScreenDoesNotBumpTwice() async {
        let provider = GatedWeather(gated: false)
        let center = ForecastCenter(provider: provider)
        let c = spots(1)[0]
        _ = await center.load(c)
        provider.fail(with: .offline(.openWeather))
        _ = await center.refresh(c)
        let afterFirstFailure = center.revision          // the banner appeared
        _ = await center.refresh(c)
        #expect(center.revision == afterFirstFailure)    // same forecast, same banner
    }

    @Test func aForcedRequestJoinsTheFetchAlreadyRunning() async {
        let provider = GatedWeather()
        let center = ForecastCenter(provider: provider)
        let c = spots(1)[0]
        center.request(c)
        center.request(c, force: true)
        center.retryFailed()
        await waitUntil { provider.waitingCount >= 1 }
        provider.releaseAll()
        _ = await center.load(c)
        #expect(provider.calls.count == 1)
        // The finished fetch cleared its own slot, so a later forced request really fetches again.
        provider.releaseAll()
        center.request(c, force: true)
        await waitUntil { provider.waitingCount == 1 }
        provider.releaseAll()
        _ = await center.refresh(c)
        #expect(provider.calls.count == 2)
    }

    @Test func requestAllFetchesEachPlaceOnce() async {
        let provider = GatedWeather(gated: false)
        let center = ForecastCenter(provider: provider)
        let batch = spots(5)
        center.requestAll(batch + batch + [Coordinate(latitude: batch[0].latitude + 0.0001, longitude: batch[0].longitude)])   // same 3 dp key as the first
        center.requestAll(batch)
        await waitUntil { batch.allSatisfy { center.state(for: $0).forecast != nil } }
        center.requestAll(batch)
        #expect(provider.calls.count == 5)
    }

    @Test func aProviderThatThrowsCancellationOnItsOwnDoesNotWedgeThePlace() async {
        let provider = GatedWeather(gated: false)
        let center = ForecastCenter(provider: provider)
        let c = spots(1)[0]
        provider.throwCancellation(true)
        center.request(c)
        await waitUntil("the abandoned fetch cleared") { provider.calls.count == 1 && center.state(for: c) == .loading && !center.isFetching(c) }
        provider.throwCancellation(false)
        center.request(c)
        await waitUntil("a later request fetches") { center.state(for: c).forecast != nil }
        #expect(provider.calls.count == 2)
    }

    @Test func invalidatingMidFlightDropsTheLateResult() async {
        let provider = GatedWeather()
        let center = ForecastCenter(provider: provider)
        let c = spots(1)[0]
        center.request(c)
        await waitUntil { provider.waitingCount == 1 }
        center.invalidateAll()
        let after = center.revision
        provider.releaseAll()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(center.state(for: c) == .loading && center.revision == after && center.lastGood.isEmpty)
        center.request(c)                                  // and the place can be asked again
        await waitUntil { provider.waitingCount == 1 }
        provider.releaseAll()
        await waitUntil { center.state(for: c).forecast != nil }
    }

    @Test func seedingBumpsOnlyWhenSomethingNewIsShown() async {
        let center = ForecastCenter(provider: GatedWeather(gated: false))
        let c = spots(1)[0]
        let saved = Forecast(coordinate: c, hours: [], days: [], fetchedAt: Date(timeIntervalSince1970: 1_700_000_000), source: .openWeather)
        center.seed(saved, for: c)
        #expect(center.revision == 1 && center.state(for: c).forecast == saved)
        center.seed(saved, for: c)
        #expect(center.revision == 1)
        // An ordinary request still refetches a seeded place.
        _ = await center.load(c)
        #expect(center.state(for: c).forecast?.fetchedAt == Date(timeIntervalSince1970: 1_790_000_000))
    }

    @Test func statusMovesOkToFailedAndBackWithTheRetry() async {
        let provider = GatedWeather(gated: false)
        let center = ForecastCenter(provider: provider)
        let c = spots(1)[0]
        provider.fail(with: .keyRejected(.openWeather))
        _ = await center.load(c)
        #expect(center.status == .failed(.keyRejected(.openWeather), lastUpdate: nil) && center.didFail(c))
        provider.fail(with: nil)
        center.retryFailed()
        await waitUntil { center.state(for: c).forecast != nil }
        #expect(center.status == .ok && !center.didFail(c))
    }
}

/// Records which thread the wire call (and so everything after it, the JSON decoding and mapping) runs on.
private final class ThreadNoting: HTTPTransport {
    let onMain = Mutex<[Bool]>([])
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        onMain.withLock { $0.append(Thread.isMainThread) }
        let body = #"{"timezone_offset":0,"hourly":[{"dt":1790000000,"clouds":20}]}"#
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

@MainActor
@Suite struct ForecastDecodingThreadTests {
    @Test func fetchingAndDecodingNeverRunOnTheMainActor() async {
        let transport = ThreadNoting()
        let keys = APIKeyResolver(store: InMemoryAPIKeyStore([.openWeather: "k"]), environment: { [:] }, launchArgument: { _ in nil })
        let service = OpenWeatherService(keys: keys, transport: transport, cache: ProviderCache(directory: nil, validity: .throughNextClockHour),
                                         budget: CallBudget(defaults: UserDefaults(suiteName: "iter.tests.\(UUID().uuidString)")!))
        let center = ForecastCenter(provider: service)
        let state = await center.load(spots(1)[0])
        #expect(state.forecast?.hours.count == 1)
        #expect(transport.onMain.withLock { $0 } == [false])
    }
}
