// The example of the PostHogEncoding module's landing article
// (Sources/PostHogEncoding/PostHogEncoding.docc/PostHogEncoding.md), verbatim, so the article cannot
// drift from the code.

import DestinationTesting
import EventMacros
import Foundation
import HTTPDestinations
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
        let postHogHost = try #require(URL(string: "https://posthog.example.com"))
        let projectToken = "phc_example"
        let memory = InMemoryDestination()
        let recording = Tracker(enrichers: [.sessions()])
        let recordingDelivery = recording.records.batch().deliver(to: memory)
        recording.track(SignedUp(plan: "pro"))
        await recording.finish()
        try await recordingDelivery.execute()

        let plan = try TrackingPlan()
        let postHog = try HTTPDestination.postHog(
            projectToken: projectToken,
            host: postHogHost,  // https://us.i.posthog.com, https://eu.i.posthog.com or your own
            plan: plan)
        let tracker = Tracker(enrichers: [.sessions()])
        let delivery = tracker.records.batch().deliver(to: postHog)

        // Nothing is tracked through `tracker`, so nothing is sent and the example runs without a
        // network. The same factory, given a transport that records requests, is checked against
        // the recorded batch instead.
        await tracker.finish()
        try await delivery.execute()
        let transport = ScriptedTransport([.status(.ok)])
        let recorded = try HTTPDestination.postHog(projectToken: projectToken, host: postHogHost, plan: plan, transport: transport)
        await recorded.receive(memory.records)
        let expectedURL = "https://posthog.example.com/batch/"
        let request = try #require(transport.requests.first)
        let json = try #require(try JSONSerialization.jsonObject(with: request.body) as? [String: Any])
        let events = try #require(json["batch"] as? [[String: Any]])
        let signedUp = try #require(events.first { $0["event"] as? String == "signed_up" })
        let properties = try #require(signedUp["properties"] as? [String: Any])
        let session = try #require(memory.records.first?.context[SessionKey.self])
        let expectedDistinctID = session.uuidString.lowercased()
        let expectedPlan = "pro"

        #expect(request.request.url?.absoluteString == expectedURL)
        #expect(transport.requests.count == 1)
        #expect(json["api_key"] as? String == projectToken)
        #expect(signedUp["distinct_id"] as? String == expectedDistinctID)
        #expect(properties["$session_id"] as? String == expectedDistinctID)
        #expect(properties["plan"] as? String == expectedPlan)
    }
}
