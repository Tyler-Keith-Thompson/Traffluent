// The example of the PostHogEncoding module's landing article
// (Sources/PostHogEncoding/PostHogEncoding.docc/PostHogEncoding.md), verbatim, so the article cannot
// drift from the code.

import EventMacros
import Foundation
import HTTPDestinations
import Instrumentation
import PostHogEncoding
import Testing
import TrackingPlans
import Traffluent

@Suite("PostHogEncoding module examples", .timeLimit(.minutes(1)))
struct PostHogEncodingModuleExamplesTests {
    @Event(name: "signed_up")
    struct SignedUp {
        var plan: String
    }

    @Test("Sending to PostHog")
    func sendingToPostHog() async throws {
        let postHogBatchURL = try #require(URL(string: "https://posthog.example.com/batch/"))
        let projectToken = "phc_example"
        let memory = InMemoryDestination()
        let recording = Tracker(enrichers: [.sessions()])
        let recordingDelivery = recording.records.batch().deliver(to: memory)
        recording.track(SignedUp(plan: "pro"))
        await recording.finish()
        try await recordingDelivery.execute()

        let plan = try TrackingPlan(schemas: [SignedUp.schema, SessionStarted.schema, SessionEnded.schema])
        let encoder = PostHogBatchEncoder(projectToken: projectToken, plan: plan)
        let postHog = HTTPDestination(
            endpoint: postHogBatchURL,  // https://us.i.posthog.com/batch/, https://eu.i.posthog.com/batch/ or your own
            instrument: NoOpInstrument(),  // so no trace context goes to PostHog in the header fields
            encoder: encoder)
        let tracker = Tracker(enrichers: [.sessions()])
        let delivery = tracker.records.batch().deliver(to: postHog)

        // Nothing is tracked through `tracker`, so nothing is sent and the example runs without a
        // network; the encoder is checked against the recorded batch instead.
        await tracker.finish()
        try await delivery.execute()
        let actual = encoder.batch(of: memory.records)
        let body = try #require(actual.body)
        let json = try #require(try JSONSerialization.jsonObject(with: body.body) as? [String: Any])
        let events = try #require(json["batch"] as? [[String: Any]])
        let signedUp = try #require(events.first { $0["event"] as? String == "signed_up" })
        let properties = try #require(signedUp["properties"] as? [String: Any])
        let session = try #require(memory.records.first?.context[SessionKey.self])
        let expectedDistinctID = session.uuidString.lowercased()
        let expectedPlan = "pro"

        #expect(actual.skippedRecords.isEmpty)
        #expect(json["api_key"] as? String == projectToken)
        #expect(signedUp["distinct_id"] as? String == expectedDistinctID)
        #expect(properties["$session_id"] as? String == expectedDistinctID)
        #expect(properties["plan"] as? String == expectedPlan)
    }
}
