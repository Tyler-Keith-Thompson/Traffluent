// The "Tracking Events" article's (Sources/Traffluent/Traffluent.docc/TrackingEvents.md) example
// of `Tracker.bootstrap`, verbatim. An exit test, in a file of its own: its body runs in a child
// process, which iOS, tvOS, watchOS and visionOS cannot start. A child process because the
// bootstrapped tracker is the process's default for good, and nothing can reset it, so
// bootstrapping in the test process would change `Tracker.current` for every other test running
// beside it. No test in the test process calls `Tracker.bootstrap`.

import Foundation
import Testing
import Traffluent

// Private: its events share their names with other events of this test target, and @Event
// leaves a private type's events out of the link check of names (DefiningEvents, Limits).
@Suite("Tracking events examples: bootstrap", .timeLimit(.minutes(1)))
private struct TrackingEventsExamplesExitTests {
    @Event
    struct SignedUp {
        var plan: String
    }

    @Test("Tracking from a detached task through the bootstrapped tracker")
    func trackingThroughTheBootstrappedTracker() async {
        await #expect(processExitsWith: .success) {
            let tracker = Tracker()
            try Tracker.bootstrap(tracker)
            let upload = Task.detached {
                Tracker.current.track(SignedUp(plan: "pro"))  // tracked by tracker
            }
            await upload.value
            await tracker.finish()
            let expected = ["pro"]

            var actual: [String] = []
            for await record in tracker.records {
                actual.append((record.event as? SignedUp)?.plan ?? "")
            }
            guard actual == expected else { exit(EXIT_FAILURE) }
        }
    }
}
