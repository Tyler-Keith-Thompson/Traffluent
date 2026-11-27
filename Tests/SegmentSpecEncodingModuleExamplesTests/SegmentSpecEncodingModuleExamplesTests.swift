// The example of the SegmentSpecEncoding module's landing article
// (Sources/SegmentSpecEncoding/SegmentSpecEncoding.docc/SegmentSpecEncoding.md), verbatim, so the
// article cannot drift from the code.

import DestinationTesting
import EventMacros
import Foundation
import HTTPDestinations
import SegmentSpecEncoding
import Testing
import TrackingPlans
import Traffluent

@Suite("SegmentSpecEncoding module examples", .timeLimit(.minutes(1)))
struct SegmentSpecEncodingModuleExamplesTests {
    @Event(name: "signed_up")
    struct SignedUp {
        var plan: String
    }

    @Test("Sending to a Segment-spec endpoint")
    func sendingToSegment() async throws {
        let writeKey = "testwritekey"
        let memory = InMemoryDestination()
        let recording = Tracker(enrichers: [.sessions()])
        let recordingDelivery = recording.records.batch().deliver(to: memory)
        recording.track(SignedUp(plan: "pro"))
        await recording.finish()
        try await recordingDelivery.execute()

        let plan = try TrackingPlan()
        let segment = try HTTPDestination.segment(
            writeKey: writeKey,
            region: .us,  // or .eu, where the workspace is
            plan: plan)
        let tracker = Tracker(enrichers: [.sessions()])
        let delivery = tracker.records.batch().deliver(to: segment)

        // Nothing is tracked through `tracker`, so nothing is sent and the example runs without a
        // network. The same factory, given a transport that records requests, is checked against
        // the recorded batch instead.
        await tracker.finish()
        try await delivery.execute()
        let transport = ScriptedTransport([.status(.ok)])
        let recorded = try HTTPDestination.segment(writeKey: writeKey, region: .us, plan: plan, transport: transport)
        await recorded.receive(memory.records)
        let expectedURL = "https://api.segment.io/v1/batch"
        let expectedAuthorization = "Basic dGVzdHdyaXRla2V5Og=="
        let request = try #require(transport.requests.first)
        let calls = try #require((try JSONSerialization.jsonObject(with: request.body) as? [String: Any])?["batch"] as? [[String: Any]])
        let signedUp = try #require(calls.first { $0["event"] as? String == "signed_up" })
        let properties = try #require(signedUp["properties"] as? [String: Any])
        let session = try #require(memory.records.first?.context[SessionKey.self])
        let expectedAnonymousID = session.uuidString.lowercased()
        let expectedPlan = "pro"

        #expect(request.request.url?.absoluteString == expectedURL)
        #expect(request.request.headerFields[.authorization] == expectedAuthorization)
        #expect(transport.requests.count == 1)
        #expect(signedUp["type"] as? String == "track")
        #expect(signedUp["anonymousId"] as? String == expectedAnonymousID)
        #expect(signedUp["userId"] == nil)
        #expect(properties["plan"] as? String == expectedPlan)
    }
}
