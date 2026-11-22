// The README's examples, verbatim, so the README cannot drift from the code.

import Traffluent
import Testing

@Suite("README examples", .timeLimit(.minutes(1)))
struct READMEExamplesTests {
    struct SignedUp: Event {
        var plan: String
    }

    @Test("Usage")
    func usage() async throws {
        let pipeline = Pipeline(ConsoleDestination())
        pipeline.track(SignedUp(plan: "pro"))
        pipeline.finish()
        try await pipeline.run().execute()  // prints: SignedUp SignedUp(plan: "pro")
    }

    @Test("Tracking from anywhere")
    func trackingFromAnywhere() async throws {
        let pipeline = Pipeline(ConsoleDestination())
        withTracker(Tracker(pipeline)) {
            Tracker.current.track(SignedUp(plan: "pro"))
        }
        pipeline.finish()
        try await pipeline.run().execute()  // prints: SignedUp SignedUp(plan: "pro")
    }
}
