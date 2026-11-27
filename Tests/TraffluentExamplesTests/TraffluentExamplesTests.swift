// The examples of the umbrella catalog's landing page
// (Sources/Traffluent/Traffluent.docc/Traffluent.md), verbatim, so the page cannot drift from the
// code. Its App, which bootstraps the tracker, is in TraffluentExamplesExitTests.swift.

import Foundation
import SystemPackage
import Testing
import TrackingPlans
import Traffluent

@Suite("Landing page examples", .timeLimit(.minutes(1)))
struct TraffluentExamplesTests {
    @Event(name: "product_added_to_cart")
    struct ProductAddedToCart {
        var productID: String
        @Constrained(.minimum(1), .maximum(10))
        var quantity: Int
    }

    @Event(name: "signed_up")
    struct SignedUp {
        var plan: String
        var email: Sensitive<String>
    }

    @Test("startAnalytics opens the store, builds the tracker and starts its delivery, which ends when the tracker finishes")
    func startAnalyticsBuildsTheTracker() async throws {
        let collectorURL = try #require(URL(string: "https://collector.example.com/v1/batches"))
        let apiKey = "k3y"
        let savedDecisions: [ConsentCategory: ConsentStatus] = [.analytics: .granted]
        // The page's store uses the default directory; this one uses a scratch directory so the
        // test leaves nothing behind.
        let directory = FilePath(NSTemporaryDirectory()).appending("TraffluentExamplesTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }

        func startAnalytics(consent: Consent) throws -> Tracker {
            // The plan and the store each take every @Event in the app, and the library's own.
            let plan = try TrackingPlan()
            // Records wait on disk until they are delivered, across launches.
            let store = try SegmentStore(directory: directory)
            // Every event gets its session, and the app, device, OS, locale and network it was tracked on.
            let tracker = Tracker(
                store: store,
                consent: consent,
                enrichers: [.sessions(), .application(), .device(), .operatingSystem(), .locale(), .network()])

            let collector = HTTPDestination(
                endpoint: collectorURL,
                headerFields: [.authorization: "Bearer \(apiKey)"],
                encoder: CollectorBatchEncoder(plan: plan))
            // Analytics events only, without their email addresses, 20 at a time or every 30 seconds.
            let delivery = tracker.records.batch().deliver(
                to: collector.accepting(.analytics).redactingSensitiveValues())
            Task {
                do {
                    try await delivery.execute()  // for the life of the app
                } catch {
                    print("Delivery stopped: \(error)")
                }
            }

            // Every event that won't arrive, and why.
            let rejections = tracker.rejectionReports
            let consentDrops = consent.dropReports
            let storeDrops = store.dropReports
            let collectorDrops = collector.dropReports
            Task {
                await withDiscardingTaskGroup { group in
                    group.addTask { for await report in rejections { print("Rejected: \(report)") } }
                    group.addTask { for await report in consentDrops { print("Not consented: \(report)") } }
                    group.addTask { for await report in storeDrops { print("Not stored: \(report)") } }
                    group.addTask { for await report in collectorDrops { print("Not sent: \(report)") } }
                }
            }
            return tracker
        }

        // Only a rejected event is tracked, so nothing is sent and the example runs without a
        // network.
        let sut = try startAnalytics(consent: Consent(savedDecisions))
        sut.track(ProductAddedToCart(productID: "canvas-tote", quantity: 0))
        await sut.finish()

        let actual = FileManager.default.fileExists(atPath: directory.string)
        #expect(actual)
    }

    @Test("The page's events, through the collector's modifiers, encode with its plan, the email address left out")
    func eventsEncodeWithThePlan() async throws {
        let plan = try TrackingPlan()
        let memory = InMemoryDestination()
        let tracker = Tracker(enrichers: [.sessions()])
        let delivery = tracker.records.batch().deliver(
            to: memory.accepting(.analytics).redactingSensitiveValues())
        let email = "ada@example.com"
        let expectedNames = [ProductAddedToCart.name, SessionStarted.name, SignedUp.name].sorted()

        tracker.track(ProductAddedToCart(productID: "canvas-tote", quantity: 1))
        tracker.track(SignedUp(plan: "plus", email: Sensitive(email)))
        await tracker.finish()
        try await delivery.execute()
        let actual = CollectorBatchEncoder(plan: plan).batch(of: memory.records)

        let body = try #require(actual.body)
        let text = try #require(String(data: body.body, encoding: .utf8))
        let actualNames = Set(memory.records.map { type(of: $0.event).name }).sorted()
        #expect(actual.skippedRecords.isEmpty)
        #expect(actualNames == expectedNames)
        #expect(!text.contains(email))
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
