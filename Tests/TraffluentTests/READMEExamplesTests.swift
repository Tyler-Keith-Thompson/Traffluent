// The README's examples, verbatim, so the README cannot drift from the code.

import Instrumentation
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

    enum ScreenKey: ServiceContextKey {
        typealias Value = String
    }

    @Test("Context and enrichers")
    func contextAndEnrichers() async throws {
        let screen = Enricher { context in
            context[ScreenKey.self] = "Checkout"
        }
        let pipeline = Pipeline(ConsoleDestination(), enrichers: [screen])
        pipeline.track(SignedUp(plan: "pro"))  // its record's context[ScreenKey.self] is "Checkout"
        pipeline.finish()
        try await pipeline.run().execute()
    }
}
