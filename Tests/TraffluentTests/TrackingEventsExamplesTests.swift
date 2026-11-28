// The examples of the "Tracking Events" article
// (Sources/Traffluent/Traffluent.docc/TrackingEvents.md), verbatim, so the article cannot drift from
// the code.

import Instrumentation
import Testing
import Traffluent

// Private: its events share their names with other events of this test target, and @Event
// leaves a private type's events out of the link check of names (DefiningEvents, Limits).
@Suite("Tracking events examples", .timeLimit(.minutes(1)))
private struct TrackingEventsExamplesTests {
    @Event
    struct SignedUp {
        var plan: String
    }

    @Test("Tracking and delivering")
    func trackingAndDelivering() async throws {
        let tracker = Tracker()
        let delivery = tracker.records.batch().deliver(to: ConsoleDestination())
        tracker.track(SignedUp(plan: "pro"))
        await tracker.finish()
        try await delivery.execute()  // prints: SignedUp SignedUp(plan: "pro")
    }

    @Test("Batching")
    func batching() async throws {
        let tracker = Tracker()
        let delivery = try tracker.records
            .batch(strategy: .either(.count(50), .time(interval: .seconds(10), clock: ContinuousClock())))
            .deliver(to: ConsoleDestination(), batchBufferLimit: 10)
        await tracker.finish()
        try await delivery.execute()
    }

    @Test("Tracking from anywhere")
    func trackingFromAnywhere() async throws {
        let tracker = Tracker()
        withTracker(tracker) {
            Tracker.current.track(SignedUp(plan: "pro"))
        }
        await tracker.finish()
        try await tracker.records.batch().deliver(to: ConsoleDestination()).execute()  // prints: SignedUp SignedUp(plan: "pro")
    }

    @Test("Tracking from a detached task")
    func trackingFromADetachedTask() async throws {
        let tracker = Tracker()
        let upload = Task.detached { [tracker] in
            tracker.track(SignedUp(plan: "pro"))
        }
        await upload.value
        await tracker.finish()
        let expected = ["pro"]

        var actual: [String] = []
        for await record in tracker.records {
            actual.append((record.event as? SignedUp)?.plan ?? "")
        }
        #expect(actual == expected)
    }

    enum ExperimentKey: ServiceContextKey {
        typealias Value = String
    }

    @Test("Context and enrichers")
    func contextAndEnrichers() async throws {
        let experiment = Enricher { context in
            context[ExperimentKey.self] = "new-checkout"
        }
        let tracker = Tracker(enrichers: [experiment])
        tracker.track(SignedUp(plan: "pro"))  // its record's context[ExperimentKey.self] is "new-checkout"
        await tracker.finish()

        var records = tracker.records.makeAsyncIterator()
        let record = try #require(await records.next())
        #expect(record.context[ExperimentKey.self] == "new-checkout")
    }
}
