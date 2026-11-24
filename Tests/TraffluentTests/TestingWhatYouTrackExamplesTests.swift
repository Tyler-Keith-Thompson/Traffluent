// The example of the "Testing What Your Code Tracks" article
// (Sources/Traffluent/Traffluent.docc/TestingWhatYouTrack.md), verbatim, so the article cannot
// drift from the code.

import Testing
import TrackerTesting
import Traffluent

@Suite("Testing what your code tracks examples", .timeLimit(.minutes(1)))
struct TestingWhatYouTrackExamplesTests {
    // The article states that `SignedUp` is `Equatable`.
    struct SignedUp: Event, Equatable {
        var plan: String
    }

    @Test func signingUpTracksThePlan() async {
        let tracked = await withRecordingTracker {
            Tracker.current.track(SignedUp(plan: "pro"))
        }
        #expect(tracked.events(of: SignedUp.self) == [SignedUp(plan: "pro")])
    }
}
