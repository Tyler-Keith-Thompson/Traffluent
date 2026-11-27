// The README's quick start, verbatim: `startAnalytics()` and the call that tracks through it. An
// exit test, in a file of its own: its body runs in a child process, which iOS, tvOS, watchOS and
// visionOS cannot start. A child process because `startAnalytics()` bootstraps its tracker, which
// stays the process's default for good, so bootstrapping in the test process would change
// `Tracker.current` for every other test running beside it.

import Foundation
import Testing
import TrackingPlans
import Traffluent

@Suite("README examples: startAnalytics", .timeLimit(.minutes(1)))
struct READMEExamplesExitTests {
    @Event(name: "product_added_to_cart")
    struct ProductAddedToCart {
        var productID: String
        @Constrained(.minimum(1), .maximum(10))
        var quantity: Int
    }

    @Test("startAnalytics bootstraps its tracker, so a second bootstrap throws, and Tracker.current tracks through it")
    func startAnalyticsBootstrapsItsTracker() async {
        await #expect(processExitsWith: .success) {
            // The README leaves the endpoint and key to the app. The child process exits before
            // the delivery's first batch is due (20 records or 30 seconds), so nothing is sent.
            guard let collectorURL = URL(string: "https://collector.example.com/v1/batches") else {
                exit(EXIT_FAILURE)
            }
            let apiKey = "k3y"
            let expectedError: TrackerAlreadyBootstrapped? = TrackerAlreadyBootstrapped()

            func startAnalytics() throws {
                // Every @Event in the app, and the library's own, such as the sessions'.
                let plan = try TrackingPlan()
                // Every event gets its session, and the app, device, OS, locale and network it was tracked on.
                let tracker = Tracker(
                    enrichers: [.sessions(), .application(), .device(), .operatingSystem(), .locale(), .network()])
                let collector = HTTPDestination(
                    endpoint: collectorURL,
                    headerFields: [.authorization: "Bearer \(apiKey)"],
                    encoder: CollectorBatchEncoder(plan: plan))
                // Analytics events only, with sensitive values left out, 20 at a time or every 30 seconds.
                let delivery = tracker.records.batch().deliver(
                    to: collector.accepting(.analytics).redactingSensitiveValues())
                Task { try? await delivery.execute() }  // for the life of the app
                try Tracker.bootstrap(tracker)  // what `Tracker.current` falls back to, anywhere in the app
            }

            // Once, as the app launches; then track from any code.
            try startAnalytics()
            Tracker.current.track(ProductAddedToCart(productID: "canvas-tote", quantity: 1))
            let actualError: TrackerAlreadyBootstrapped?
            do throws(TrackerAlreadyBootstrapped) {
                try Tracker.bootstrap(Tracker())
                actualError = nil
            } catch {
                actualError = error
            }

            guard actualError == expectedError else { exit(EXIT_FAILURE) }
        }
    }
}
