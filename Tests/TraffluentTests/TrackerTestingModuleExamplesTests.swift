// The example of the TrackerTesting module's landing article
// (Sources/TrackerTesting/TrackerTesting.docc/TrackerTesting.md), verbatim, so the article cannot
// drift from the code. The example is itself a test.

import Testing
import TrackerTesting
import Traffluent

@Suite("TrackerTesting module examples", .timeLimit(.minutes(1)))
struct TrackerTestingModuleExamplesTests {
    struct CheckoutStarted: Event {
        var cartSize: Int
    }

    @Test func checkingOutTracksTheCartSize() async {
        let tracked = await withRecordingTracker { tracker in
            tracker.track(CheckoutStarted(cartSize: 3))
            return "done"
        }
        #expect(tracked.value == "done")
        #expect(tracked.names == ["CheckoutStarted"])
        #expect(tracked.events(of: CheckoutStarted.self).map(\.cartSize) == [3])
    }
}
