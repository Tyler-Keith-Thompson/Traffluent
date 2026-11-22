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
}
