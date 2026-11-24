import Foundation
import Testing
import IterFeatures
import IterModel
@testable import IterScreens

@Suite("Sample data wording")
struct SampleDataTextTests {
    let loc = Locale(identifier: "en_US")

    @Test func liveWordSaysSampleInSampleMode() {
        #expect(SampleDataText.liveWord(sample: false, locale: loc) == "Live")
        #expect(SampleDataText.liveWord(sample: true, locale: loc) == "Sample")
    }

    @Test func driveBasisNeverSaysTrafficInSampleMode() {
        #expect(DriveBasis.sample.label == "Sample drive time")
        #expect(DriveBasis.trafficAware(departing: Date()).label == "With traffic")
        #expect(DriveBasis.typical.label == "Typical")
    }
}
