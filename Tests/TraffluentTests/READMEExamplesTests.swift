// The README's quick start, verbatim, so the README cannot drift from the code. Its
// `startAnalytics()`, which bootstraps the tracker, is in READMEExamplesExitTests.swift; these
// tests run its event, plan, tracker and modifiers in this process, with an in-memory destination
// in place of the collector, so nothing is sent over the network.

import Testing
import TrackingPlans
import Traffluent

@Suite("README examples", .timeLimit(.minutes(1)))
struct READMEExamplesTests {
    @Event(name: "product_added_to_cart")
    struct ProductAddedToCart {
        var productID: String
        @Constrained(.minimum(1), .maximum(10))
        var quantity: Int
    }

    @Test("The quick start's tracker, through the collector's modifiers, sends records its plan encodes")
    func recordsEncodeWithThePlan() async throws {
        let plan = try TrackingPlan(
            schemas: [ProductAddedToCart.schema, SessionStarted.schema, SessionEnded.schema])
        // Every event gets its session, and the app, device, OS, locale and network it was tracked on.
        let tracker = Tracker(
            enrichers: [.sessions(), .application(), .device(), .operatingSystem(), .locale(), .network()])
        // The README's collector posts to a server; this one keeps the records in memory.
        let memory = InMemoryDestination()
        // Analytics events only, with sensitive values left out, 20 at a time or every 30 seconds.
        let delivery = tracker.records.batch().deliver(
            to: memory.accepting(.analytics).redactingSensitiveValues())
        let expectedNames = [ProductAddedToCart.name, SessionStarted.name].sorted()

        // The README tracks through the bootstrapped `Tracker.current`, which a test in this
        // process mustn't set (READMEExamplesExitTests runs it); this tracks through the tracker.
        tracker.track(ProductAddedToCart(productID: "canvas-tote", quantity: 1))
        await tracker.finish()
        try await delivery.execute()
        let actual = CollectorBatchEncoder(plan: plan).batch(of: memory.records)

        let actualNames = memory.records.map { type(of: $0.event).name }.sorted()
        #expect(actual.body != nil)
        #expect(actual.skippedRecords.isEmpty)
        #expect(actualNames == expectedNames)
    }

    @Test("A ProductAddedToCart with a quantity past 10 is rejected and never delivered")
    func quantityConstraint() async throws {
        let memory = InMemoryDestination()
        let tracker = Tracker()
        let delivery = tracker.records.batch().deliver(to: memory)
        let expectedQuantities = [10]
        let expectedRejectionCount = 1

        tracker.track(ProductAddedToCart(productID: "canvas-tote", quantity: 11))
        tracker.track(ProductAddedToCart(productID: "canvas-tote", quantity: 10))
        await tracker.finish()
        try await delivery.execute()

        var actualRejectionCount = 0
        for await _ in tracker.rejectionReports {
            actualRejectionCount += 1
        }
        #expect(memory.events(of: ProductAddedToCart.self).map(\.quantity) == expectedQuantities)
        #expect(actualRejectionCount == expectedRejectionCount)
    }
}
