// The example of the HTTPDestinations module's landing article
// (Sources/HTTPDestinations/HTTPDestinations.docc/HTTPDestinations.md), verbatim, so the article
// cannot drift from the code.

import Foundation
import HTTPDestinations
import Testing
import Traffluent

@Suite("HTTPDestinations module examples", .timeLimit(.minutes(1)))
struct HTTPDestinationsModuleExamplesTests {
    @Event
    struct SignedUp {
        var plan: String
    }

    struct PlansEncoder: BatchEncoder {
        func encode(_ batch: [EventRecord]) -> EncodedBatch {
            let plans = batch.compactMap { ($0.event as? SignedUp)?.plan }
            return EncodedBatch(body: Data(plans.joined(separator: "\n").utf8), contentType: "text/plain")
        }
    }

    @Test("Sending to a server of your own format")
    func sendingToAServer() async throws {
        let endpointURL = try #require(URL(string: "https://analytics.example.com/batches"))
        let token = "t0ken"
        let tracker = Tracker()

        let server = HTTPDestination(
            endpoint: endpointURL,
            headerFields: [.authorization: "Bearer \(token)"],
            encoder: PlansEncoder(),
            backoff: ExponentialBackoff(initialDelay: .seconds(2), maximumDelay: .seconds(120)))
        let drops = server.dropReports
        let watching = Task {
            for await drop in drops {
                print("Dropped a batch: \(drop)")
            }
        }
        let delivery = tracker.records.batch().deliver(to: server)

        // Nothing is tracked, so nothing is sent and the example runs without a network.
        await tracker.finish()
        try await delivery.execute()
        watching.cancel()
        await watching.value
    }

    @Test("The example's encoder writes one plan per line")
    func plansEncoder() async throws {
        let memory = InMemoryDestination()
        let tracker = Tracker()
        let delivery = tracker.records.batch().deliver(to: memory)
        tracker.track(SignedUp(plan: "pro"))
        tracker.track(SignedUp(plan: "team"))
        await tracker.finish()
        try await delivery.execute()
        let expected = EncodedBatch(body: Data("pro\nteam".utf8), contentType: "text/plain")

        let actual = PlansEncoder().encode(memory.records)

        #expect(actual == expected)
    }
}
