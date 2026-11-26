// The example of the CollectorEncoding module's landing article
// (Sources/CollectorEncoding/CollectorEncoding.docc/CollectorEncoding.md), verbatim, so the article
// cannot drift from the code.

import CollectorEncoding
import EventMacros
import Foundation
import HTTPDestinations
import Testing
import TrackingPlans
import Traffluent

@Suite("CollectorEncoding module examples", .timeLimit(.minutes(1)))
struct CollectorEncodingModuleExamplesTests {
    @Event(name: "signed_up")
    struct SignedUp {
        var plan: String
    }

    @Test("Sending to TraffluentCollector")
    func sendingToTheCollector() async throws {
        let collectorURL = try #require(URL(string: "https://collector.example.com/v1/batches"))
        let apiKey = "k3y"
        let tracker = Tracker()
        let memory = InMemoryDestination()
        let recording = Tracker()
        let recordingDelivery = recording.records.batch().deliver(to: memory)
        recording.track(SignedUp(plan: "pro"))
        await recording.finish()
        try await recordingDelivery.execute()

        let plan = try TrackingPlan(schemas: [SignedUp.schema])
        let encoder = CollectorBatchEncoder(plan: plan)
        let collector = HTTPDestination(
            endpoint: collectorURL,  // https://collector.example.com/v1/batches
            headerFields: [.authorization: "Bearer \(apiKey)"],
            encoder: encoder)
        let delivery = tracker.records.batch().deliver(to: collector)

        // Nothing is tracked through `tracker`, so nothing is sent and the example runs without a
        // network; the encoder is checked against the recorded batch instead.
        await tracker.finish()
        try await delivery.execute()
        let actual = encoder.batch(of: memory.records)
        let body = try #require(actual.body)
        let json = try #require(try JSONSerialization.jsonObject(with: body.body) as? [String: Any])
        let records = try #require(json["records"] as? [[String: Any]])
        let properties = try #require(records.first?["properties"] as? [String: Any])
        let expectedContentType = "application/json"
        let expectedName = "signed_up"
        let expectedPlan = "pro"

        #expect(actual.skippedRecords.isEmpty)
        #expect(body.contentType == expectedContentType)
        #expect(records.count == 1)
        #expect(records.first?["name"] as? String == expectedName)
        #expect(properties["plan"] as? String == expectedPlan)
    }
}
