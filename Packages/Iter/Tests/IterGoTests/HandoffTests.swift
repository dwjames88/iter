import Foundation
import Testing
import IterGo
import IterModel

@Test func handoffURL() {
    let h = NavigationHandoff(destination: Coordinate(latitude: 36.5786, longitude: -118.2925), name: "Mt. Whitney & Lone Pine")
    #expect(h.appleMapsURL.absoluteString == "https://maps.apple.com/?daddr=36.578600,-118.292500&dirflg=d&q=Mt.%20Whitney%20%26%20Lone%20Pine")
    let c = URLComponents(url: h.appleMapsURL, resolvingAgainstBaseURL: false)
    #expect(c?.queryItems?.first { $0.name == "q" }?.value == "Mt. Whitney & Lone Pine")
    #expect(c?.queryItems?.first { $0.name == "dirflg" }?.value == "d")
    let odd = NavigationHandoff(destination: Coordinate(latitude: -33.5, longitude: 151.25), name: "Café #1 +/=")
    let q = URLComponents(url: odd.appleMapsURL, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "q" }?.value
    #expect(q == "Café #1 +/=")
    #expect(odd.appleMapsURL.absoluteString.contains("daddr=-33.500000,151.250000"))
    #expect(NavigationHandoff(destination: h.destination, name: "x").launchOptions.count == 1)
    #expect(h.mapItem().name == "Mt. Whitney & Lone Pine")
}
