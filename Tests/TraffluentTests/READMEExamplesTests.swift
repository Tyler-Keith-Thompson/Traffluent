// The README's examples, verbatim, so the README cannot drift from the code.

import Traffluent
import Testing

@Suite("README examples")
struct READMEExamplesTests {
    struct SignedUp: Event {
        var plan: String
    }

    @Test("Usage")
    func usage() async {
        let pipeline = Pipeline(ConsoleDestination())
        await pipeline.track(SignedUp(plan: "pro"))  // prints: SignedUp SignedUp(plan: "pro")
    }
}
