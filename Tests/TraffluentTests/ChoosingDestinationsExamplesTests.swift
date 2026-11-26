// The examples of the "Choosing Destinations" article
// (Sources/Traffluent/Traffluent.docc/ChoosingDestinations.md), verbatim, so the article cannot
// drift from the code.

import Foundation
import Instrumentation
import PostHogEncoding
import Testing
import TrackingPlans
import Traffluent

@Suite("Choosing destinations examples", .timeLimit(.minutes(1)))
struct ChoosingDestinationsExamplesTests {
    @Event
    struct SignedIn {
        var email: Sensitive<String>
    }

    @Event
    struct SignedUp {
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

@Suite("Choosing destinations examples: PostHog", .timeLimit(.minutes(1)))
struct ChoosingDestinationsPostHogExamplesTests {
    @Event(name: "signed_up")
    struct SignedUp {
        var plan: String
    }

    @Test("PostHog")
    func postHog() async throws {
        let postHogBatchURL = try #require(URL(string: "https://posthog.example.com/batch/"))
        let projectToken = "phc_example"

        let plan = TrackingPlan(schemas: [SignedUp.schema, SessionStarted.schema, SessionEnded.schema])
        let postHog = HTTPDestination(
            endpoint: postHogBatchURL,  // https://us.i.posthog.com/batch/, https://eu.i.posthog.com/batch/ or your own
            instrument: NoOpInstrument(),  // so no trace context goes to PostHog in the header fields
            encoder: PostHogBatchEncoder(projectToken: projectToken, plan: plan))
        let tracker = Tracker(enrichers: [.sessions()])
        let delivery = tracker.records.batch().deliver(to: postHog)

        // Nothing is tracked, so nothing is sent and the example runs without a network.
        await tracker.finish()
        try await delivery.execute()
        let expected = [SignedUp.name, SessionStarted.name, SessionEnded.name].sorted()

        #expect(plan.schemas.map(\.name).sorted() == expected)
    }
}
