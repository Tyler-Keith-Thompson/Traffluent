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
        let tracker = Tracker()
        let delivery = tracker.records.batch().deliver(to: ConsoleDestination())
        tracker.track(SignedUp(plan: "pro"))
        tracker.finish()
        try await delivery.execute()  // prints: SignedUp SignedUp(plan: "pro")
    }

    @Test("Batching")
    func batching() async throws {
        let tracker = Tracker()
        let delivery = tracker.records
            .batch(strategy: .either(.count(50), .time(interval: .seconds(10), clock: ContinuousClock())))
            .deliver(to: ConsoleDestination(), batchBufferLimit: 10)
        tracker.finish()
        try await delivery.execute()
    }

    @Test("Tracking from anywhere")
    func trackingFromAnywhere() async throws {
        let tracker = Tracker()
        withTracker(tracker) {
            Tracker.current.track(SignedUp(plan: "pro"))
        }
        tracker.finish()
        try await tracker.records.batch().deliver(to: ConsoleDestination()).execute()  // prints: SignedUp SignedUp(plan: "pro")
    }

    enum ScreenKey: ServiceContextKey {
        typealias Value = String
    }

    @Test("Context and enrichers")
    func contextAndEnrichers() async throws {
        let screen = Enricher { context in
            context[ScreenKey.self] = "Checkout"
        }
        let tracker = Tracker(enrichers: [screen])
        tracker.track(SignedUp(plan: "pro"))  // its record's context[ScreenKey.self] is "Checkout"
        tracker.finish()
        try await tracker.records.batch().deliver(to: ConsoleDestination()).execute()
    }
}
