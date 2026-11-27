// The example of the MixpanelEncoding module's landing article
// (Sources/MixpanelEncoding/MixpanelEncoding.docc/MixpanelEncoding.md), verbatim, so the article
// cannot drift from the code.

import DestinationTesting
import EventMacros
import Foundation
import HTTPDestinations
import MixpanelEncoding
import Testing
import TrackingPlans
import Traffluent

@Suite("MixpanelEncoding module examples", .timeLimit(.minutes(1)))
struct MixpanelEncodingModuleExamplesTests {
    @Event(name: "signed_up")
    struct SignedUp {
        var plan: String
    }

    @Test("Sending to Mixpanel")
    func sendingToMixpanel() async throws {
        let projectToken = "0123456789abcdef0123456789abcdef"
        let memory = InMemoryDestination()
        let recording = Tracker(enrichers: [.sessions()])
        let recordingDelivery = recording.records.batch().deliver(to: memory)
        recording.track(SignedUp(plan: "pro"))
        await recording.finish()
        try await recordingDelivery.execute()

        let plan = try TrackingPlan()
        let mixpanel = try HTTPDestination.mixpanel(
            projectToken: projectToken,
            region: .us,  // or .eu or .india, where the project's data resides
            plan: plan)
        let tracker = Tracker(enrichers: [.sessions()])
        let delivery = tracker.records.batch().deliver(to: mixpanel)

        // Nothing is tracked through `tracker`, so nothing is sent and the example runs without a
        // network. The same factory, given a transport that records requests, is checked against
        // the recorded batch instead.
        await tracker.finish()
        try await delivery.execute()
        let transport = ScriptedTransport([.status(.ok)])
        let recorded = try HTTPDestination.mixpanel(projectToken: projectToken, region: .us, plan: plan, transport: transport)
        await recorded.receive(memory.records)
        let expectedURL = "https://api.mixpanel.com/track?ip=0"
        let request = try #require(transport.requests.first)
        let events = try #require(try JSONSerialization.jsonObject(with: request.body) as? [[String: Any]])
        let signedUp = try #require(events.first { $0["event"] as? String == "signed_up" })
        let properties = try #require(signedUp["properties"] as? [String: Any])
        let session = try #require(memory.records.first?.context[SessionKey.self])
        let expectedDistinctID = session.uuidString.lowercased()
        let expectedPlan = "pro"

        #expect(request.request.url?.absoluteString == expectedURL)
        #expect(transport.requests.count == 1)
        #expect(properties["token"] as? String == projectToken)
        #expect(properties["distinct_id"] as? String == expectedDistinctID)
        #expect(properties["$user_id"] == nil)
        #expect(properties["plan"] as? String == expectedPlan)
    }
}
