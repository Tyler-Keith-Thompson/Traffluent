// The example of the Destinations module's landing article
// (Sources/Destinations/Destinations.docc/Destinations.md), verbatim, so the article cannot drift
// from the code.

import Testing
import Traffluent

// Private: its events share their names with other events of this test target, and @Event
// leaves a private type's events out of the link check of names (DefiningEvents, Limits).
@Suite("Destinations module examples", .timeLimit(.minutes(1)))
private struct DestinationsModuleExamplesTests {
    @Event
    struct SignedUp: Equatable {
        var plan: String
    }

    struct Uploader: Destination {
        func receive(_ batch: [EventRecord]) async {
            // Send the batch, and return once it is somewhere it won't be lost.
        }
    }

    @Test("A destination of your own beside an in-memory one, with modifiers")
    func destinationsAndModifiers() async throws {
        let inspector = try InMemoryDestination(capacity: 500)
        let tracker = Tracker()
        let delivery = tracker.records
            .batch(strategy: .count(20))
            .deliver(
                to: Uploader().accepting(.analytics).redactingSensitiveValues().droppingCallSite(),
                inspector
            )
        tracker.track(SignedUp(plan: "pro"))
        await tracker.finish()
        try await delivery.execute()
        let received = inspector.events(of: SignedUp.self)  // [SignedUp(plan: "pro")]

        let expected = [SignedUp(plan: "pro")]
        #expect(received == expected)
    }
}
