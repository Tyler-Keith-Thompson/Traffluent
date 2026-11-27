// The example of the HeapEncoding module's landing article
// (Sources/HeapEncoding/HeapEncoding.docc/HeapEncoding.md), verbatim, so the article cannot drift
// from the code.

import DestinationTesting
import EventMacros
import Foundation
import HTTPDestinations
import HeapEncoding
import Testing
import TrackingPlans
import Traffluent

@Suite("HeapEncoding module examples", .timeLimit(.minutes(1)))
struct HeapEncodingModuleExamplesTests {
    @Event(name: "signed_up")
    struct SignedUp {
        var plan: String
    }

    @Test("Sending to Heap")
    func sendingToHeap() async throws {
        let appID = "12343283"
        let memory = InMemoryDestination()
        let recording = Tracker(enrichers: [.sessions()])
        let recordingDelivery = recording.records.batch().deliver(to: memory)
        recording.track(SignedUp(plan: "pro"))
        await recording.finish()
        try await recordingDelivery.execute()

        let plan = try TrackingPlan()
        let heap = try HTTPDestination.heap(
            appID: appID,  // the environment's ID, from Heap's project settings
            region: .us,  // or .eu, where the project's data resides
            plan: plan)
        let tracker = Tracker(enrichers: [.sessions()])
        let delivery = tracker.records.batch().deliver(to: heap)

        // Nothing is tracked through `tracker`, so nothing is sent and the example runs without a
        // network. The same factory, given a transport that records requests, is checked against
        // the recorded batch instead.
        await tracker.finish()
        try await delivery.execute()
        let transport = ScriptedTransport([.status(.ok)])
        let sut = try HTTPDestination.heap(appID: appID, region: .us, plan: plan, transport: transport)
        let record = try #require(memory.records.first { $0.name == "signed_up" })
        let session = try #require(record.context[SessionKey.self])
        let expectedURL = "https://heapanalytics.com/api/track"
        let expectedIdentity = session.uuidString.lowercased()
        let expectedKey = record.id.uuidString.lowercased()
        let expectedProperties = ["plan": "pro"]

        await sut.receive(memory.records)

        let request = try #require(transport.requests.first)
        let body = try #require(try JSONSerialization.jsonObject(with: request.body) as? [String: Any])
        let events = try #require(body["events"] as? [[String: Any]])
        let signedUp = try #require(events.first { $0["event"] as? String == "signed_up" })
        #expect(request.request.url?.absoluteString == expectedURL)
        #expect(body["app_id"] as? String == appID)
        #expect(signedUp["identity"] as? String == expectedIdentity)
        #expect(signedUp["idempotency_key"] as? String == expectedKey)
        #expect(signedUp["properties"] as? [String: String] == expectedProperties)
    }
}
