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
        static let transientStatuses: Set<TransientStatus> = []

        func requests(for batch: [EventRecord]) -> BatchRequests<Never> {
            let plans = batch.compactMap { ($0.event as? SignedUp)?.plan }
            let body = EncodedBatch(body: Data(plans.joined(separator: "\n").utf8), contentType: "text/plain")
            return BatchRequests(requests: [EncodedRequest(body: body, recordIDs: batch.map(\.id))], skippedRecords: [])
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
            backoff: try ExponentialBackoff(initialDelay: .seconds(2), maximumDelay: .seconds(120)))
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
        let expected = BatchRequests<Never>(requests: [EncodedRequest(body: EncodedBatch(body: Data("pro\nteam".utf8), contentType: "text/plain"), recordIDs: memory.records.map(\.id))], skippedRecords: [])

        let actual = PlansEncoder().requests(for: memory.records)

        #expect(actual == expected)
    }
}
