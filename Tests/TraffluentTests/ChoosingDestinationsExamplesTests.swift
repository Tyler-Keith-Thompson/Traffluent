// The example of the "Choosing Destinations" article
// (Sources/Traffluent/Traffluent.docc/ChoosingDestinations.md), verbatim, so the article cannot
// drift from the code.

import Testing
import Traffluent

@Suite("Choosing destinations examples", .timeLimit(.minutes(1)))
struct ChoosingDestinationsExamplesTests {
    struct SignedIn: Event {
        var email: Sensitive<String>
    }

    @Test("Sensitive values and call sites")
    func sensitiveValuesAndCallSites() async throws {
        let backend = InMemoryDestination()
        let vendor = InMemoryDestination()
        let tracker = Tracker()
        let delivery = tracker.records.batch().deliver(
            to: backend,
            vendor.redactingSensitiveValues().droppingCallSite()
        )
        tracker.track(SignedIn(email: Sensitive("ada@example.com")))
        await tracker.finish()
        try await delivery.execute()
        let event = backend.events(of: SignedIn.self)[0]
        let email = backend.records[0].reveal(event.email)    // "ada@example.com"
        let redacted = vendor.records[0].reveal(event.email)  // nil
        let callSite = vendor.records[0].sourceLocation       // nil

        #expect(email == "ada@example.com")
        #expect(redacted == nil)
        #expect(callSite == nil)
    }
}
