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

// "Reading batches back": a server's types of two versions of one event, at file scope as the
// article declares them.
@Event(name: "checkout_started", version: 2)
struct CheckoutStarted {
    var items: Int
    var currency: String
}

// Version 1, which releases still installed send.
private enum EarlierVersions {
    @Event(name: "checkout_started")
    struct CheckoutStarted {
        var items: Int
    }
}

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

        let plan = try TrackingPlan()
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

    @Test("Reading batches back")
    func readingBatchesBack() async throws {
        let memory = InMemoryDestination()
        let recording = Tracker(enrichers: [.sessions()])
        let recordingDelivery = recording.records.batch().deliver(to: memory)
        recording.track(SignedUp(plan: "pro"))
        await recording.finish()
        try await recordingDelivery.execute()
        let body = try #require(CollectorBatchEncoder(plan: try TrackingPlan()).batch(of: memory.records).body).body
        let destination = InMemoryDestination()

        let plan = try TrackingPlan()
        let decoder = try CollectorBatchDecoder(plan: plan)
        let batch = try decoder.batch(from: body)  // a body CollectorBatchEncoder wrote
        await destination.receive(batch.records)

        let expectedIDs = memory.records.map(\.id)
        let expectedSessions = memory.records.map { $0.context[SessionKey.self] }
        let expectedPlan = "pro"

        #expect(batch.undecodedRecords.isEmpty)
        #expect(destination.records.map(\.id) == expectedIDs)
        #expect(destination.records.map { $0.context[SessionKey.self] } == expectedSessions)
        #expect(destination.records.compactMap { ($0.event as? SignedUp)?.plan } == [expectedPlan])
    }

    @Test("Reading batches back: a record of each version is read into its own type, the earlier one in a private scope")
    func readingEarlierVersions() async throws {
        let memory = InMemoryDestination()
        let recording = Tracker()
        let recordingDelivery = recording.records.batch().deliver(to: memory)
        recording.track(EarlierVersions.CheckoutStarted(items: 1))
        recording.track(CheckoutStarted(items: 2, currency: "EUR"))
        await recording.finish()
        try await recordingDelivery.execute()
        let plan = try TrackingPlan()
        let body = try #require(CollectorBatchEncoder(plan: plan).batch(of: memory.records).body).body
        let decoder = try CollectorBatchDecoder(plan: plan)
        let expectedEarlier = 1
        let expectedCurrency = "EUR"

        let batch = try decoder.batch(from: body)

        try #require(batch.records.count == 2)
        let earlier = batch.records[0].event as? EarlierVersions.CheckoutStarted
        let current = batch.records[1].event as? CheckoutStarted
        #expect(batch.undecodedRecords.isEmpty)
        #expect(earlier?.items == expectedEarlier)
        #expect(current?.currency == expectedCurrency)
    }
}
