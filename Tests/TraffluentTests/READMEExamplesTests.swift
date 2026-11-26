// The README's example, verbatim, so the README cannot drift from the code.

import Testing
import Traffluent

@Suite("README example", .timeLimit(.minutes(1)))
struct READMEExamplesTests {
    @Event
    struct SignedUp {
        var plan: String
    }

    @Test("Example")
    func example() async throws {
        let tracker = Tracker()
        let delivery = tracker.records.batch().deliver(to: ConsoleDestination())
        tracker.track(SignedUp(plan: "pro"))
        await tracker.finish()
        try await delivery.execute()  // prints: SignedUp SignedUp(plan: "pro")
    }
}
