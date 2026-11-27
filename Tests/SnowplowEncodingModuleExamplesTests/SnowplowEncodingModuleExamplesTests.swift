// The example of the SnowplowEncoding module's landing article
// (Sources/SnowplowEncoding/SnowplowEncoding.docc/SnowplowEncoding.md), verbatim, so the article
// cannot drift from the code.

import DestinationTesting
import EventMacros
import Foundation
import HTTPDestinations
import SnowplowEncoding
import Testing
import TrackingPlans
import Traffluent

@Suite("SnowplowEncoding module examples", .timeLimit(.minutes(1)))
struct SnowplowEncodingModuleExamplesTests {
    @Event(name: "signed_up")
    struct SignedUp {
        var plan: String
    }

    @Test("Sending to Snowplow")
    func sendingToSnowplow() async throws {
        let collector = try #require(URL(string: "https://collector.example.com"))
        let memory = InMemoryDestination()
        let recording = Tracker(enrichers: [.sessions()])
        let recordingDelivery = recording.records.batch().deliver(to: memory)
        recording.track(SignedUp(plan: "pro"))
        await recording.finish()
        try await recordingDelivery.execute()

        let plan = try TrackingPlan()
        let snowplow = try HTTPDestination.snowplow(
            collector: collector,  // https://collector.example.com
            vendor: "com.example",  // the Iglu vendor the plan is exported under
            appID: "shop-ios",
            plan: plan)
        let tracker = Tracker(enrichers: [.sessions()])
        let delivery = tracker.records.batch().deliver(to: snowplow)

        // Nothing is tracked through `tracker`, so nothing is sent and the example runs without a
        // network. The same factory, given a transport that records requests, is checked against
        // the recorded batch instead.
        await tracker.finish()
        try await delivery.execute()
        let transport = ScriptedTransport([.status(.ok)])
        let recorded = try HTTPDestination.snowplow(collector: collector, vendor: "com.example", appID: "shop-ios", plan: plan, transport: transport)
        await recorded.receive(memory.records)
        let expectedURL = "https://collector.example.com/com.snowplowanalytics.snowplow/tp2"
        let request = try #require(transport.requests.first)
        let body = try #require(try JSONSerialization.jsonObject(with: request.body) as? [String: Any])
        let events = try #require(body["data"] as? [[String: Any]])
        let signedUp = try #require(events.first { ($0["ue_pr"] as? String)?.contains("iglu:com.example/signed_up/jsonschema/1-0-0") == true })
        let session = try #require(memory.records.first?.context[SessionKey.self])
        let expectedSession = session.uuidString.lowercased()
        let expectedAppID = "shop-ios"

        #expect(request.request.url?.absoluteString == expectedURL)
        #expect(signedUp["sid"] as? String == expectedSession)
        #expect(signedUp["aid"] as? String == expectedAppID)
        #expect(signedUp["duid"] == nil)
        #expect((signedUp["ue_pr"] as? String)?.contains(#""plan":"pro""#) == true)
    }
}
