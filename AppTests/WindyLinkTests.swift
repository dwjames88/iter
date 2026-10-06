import Foundation
import Testing
import IterCore
@testable import Iter

@Suite("WindyLink") struct WindyLinkTests {
    @Test func buildsTheOwnersExample() {
        let url = WindyLink.url(center: Coordinate(latitude: 37.321, longitude: -121.892), zoom: 5)
        #expect(url.absoluteString == "https://www.windy.com/?37.321,-121.892,5")
    }

    @Test func roundsToThreeDecimalPlaces() {
        let url = WindyLink.url(center: Coordinate(latitude: 37.3214, longitude: -121.8926), zoom: 9)
        #expect(url.absoluteString == "https://www.windy.com/?37.321,-121.893,9")
    }

    @Test func padsAndKeepsSigns() {
        let url = WindyLink.url(center: Coordinate(latitude: -33.5, longitude: 151), zoom: 9)
        #expect(url.absoluteString == "https://www.windy.com/?-33.500,151.000,9")
    }

    @Test func tinyNegativeNumbersAreNotNegativeZero() {
        let url = WindyLink.url(center: Coordinate(latitude: -0.0001, longitude: 0.0001), zoom: 3)
        #expect(url.absoluteString == "https://www.windy.com/?0.000,0.000,3")
    }

    @Test func zoomFollowsTheLatitudeSpan() {
        #expect(WindyLink.zoom(forLatitudeDelta: 11.25) == 5)
        #expect(WindyLink.zoom(forLatitudeDelta: 0.7) == 9)
        #expect(WindyLink.zoom(forLatitudeDelta: 45) == 3)
    }

    @Test func zoomIsClamped() {
        #expect(WindyLink.zoom(forLatitudeDelta: 170) == 3)
        #expect(WindyLink.zoom(forLatitudeDelta: 0.0001) == 11)
        #expect(WindyLink.zoom(forLatitudeDelta: 0) == 11)
        #expect(WindyLink.zoom(forLatitudeDelta: .nan) == 11)
    }
}
