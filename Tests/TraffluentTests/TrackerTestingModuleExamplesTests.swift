// The example of the TrackerTesting module's landing article
// (Sources/TrackerTesting/TrackerTesting.docc/TrackerTesting.md), verbatim, so the article cannot
// drift from the code. The example is itself a test.

import Testing
import TrackerTesting
import Traffluent

// Private: its events share their names with other events of this test target, and @Event
// leaves a private type's events out of the link check of names (DefiningEvents, Limits).
@Suite("TrackerTesting module examples", .timeLimit(.minutes(1)))
private struct TrackerTestingModuleExamplesTests {
    @Event
    struct CheckoutStarted {
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
