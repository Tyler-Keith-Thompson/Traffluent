// The examples of the "Choosing Destinations" article
// (Sources/Traffluent/Traffluent.docc/ChoosingDestinations.md), verbatim, so the article cannot
// drift from the code.

import Testing
import Traffluent

@Suite("Choosing destinations examples", .timeLimit(.minutes(1)))
struct ChoosingDestinationsExamplesTests {
    struct SignedIn: Event {
        var email: Sensitive<String>
    }

    struct SignedUp: Event {
        var plan: String
    }

    @Test("Hearing about batches a full buffer drops")
    func bufferDrops() async throws {
        let collector = InMemoryDestination()
        let tracker = Tracker()
        let (bufferDrops, bufferDropReporter) = AsyncStream.makeStream(of: BufferDropReport.self)
        let delivery = tracker.records.batch().deliver(to: collector, bufferDropReporter: bufferDropReporter)
        let watching = Task {
            for await drop in bufferDrops where drop.storedRecordCount < drop.recordCount {
                print("Lost \(drop.recordCount - drop.storedRecordCount) events tracked from \(drop.timestamps.lowerBound)")
            }
        }

        tracker.track(SignedUp(plan: "pro"))
        await tracker.finish()
        try await delivery.execute()
        bufferDropReporter.finish()
        await watching.value
        let expected = ["pro"]

        #expect(collector.events(of: SignedUp.self).map(\.plan) == expected)
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
