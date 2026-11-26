// The example of the Destinations module's landing article
// (Sources/Destinations/Destinations.docc/Destinations.md), verbatim, so the article cannot drift
// from the code.

import Testing
import Traffluent

@Suite("Destinations module examples", .timeLimit(.minutes(1)))
struct DestinationsModuleExamplesTests {
    struct SignedUp: Event, Equatable {
        var plan: String
    }

    struct Uploader: Destination {
        func receive(_ batch: [EventRecord]) async {
            // Send the batch, and return once it is somewhere it won't be lost.
        }
    }

    @Test("A destination of your own beside an in-memory one, with modifiers")
    func destinationsAndModifiers() async throws {
        let inspector = InMemoryDestination(capacity: 500)
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
