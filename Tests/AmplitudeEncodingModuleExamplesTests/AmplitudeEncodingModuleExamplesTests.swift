// The example of the AmplitudeEncoding module's landing article
// (Sources/AmplitudeEncoding/AmplitudeEncoding.docc/AmplitudeEncoding.md), verbatim, so the
// article cannot drift from the code.

import AmplitudeEncoding
import DestinationTesting
import EventMacros
import Foundation
import HTTPDestinations
import Testing
import TrackingPlans
import Traffluent

@Suite("AmplitudeEncoding module examples", .timeLimit(.minutes(1)))
struct AmplitudeEncodingModuleExamplesTests {
    @Event(name: "signed_up")
    struct SignedUp {
        var plan: String
    }

    @Test("Sending to Amplitude")
    func sendingToAmplitude() async throws {
        let apiKey = "0123456789abcdef0123456789abcdef"
        let memory = InMemoryDestination()
        let recording = Tracker(enrichers: [.sessions()])
        let recordingDelivery = recording.records.batch().deliver(to: memory)
        recording.track(SignedUp(plan: "pro"))
        await recording.finish()
        try await recordingDelivery.execute()

        let plan = try TrackingPlan()
        let amplitude = try HTTPDestination.amplitude(
            apiKey: apiKey,
            region: .us,  // or .eu, where the project's data resides
            plan: plan)
        let tracker = Tracker(enrichers: [.sessions()])
        let delivery = tracker.records.batch().deliver(to: amplitude)

        // Nothing is tracked through `tracker`, so nothing is sent and the example runs without a
        // network. The same factory, given a transport that records requests, is checked against
        // the recorded batch instead.
        await tracker.finish()
        try await delivery.execute()
        let transport = ScriptedTransport([.status(.ok)])
        let recorded = try HTTPDestination.amplitude(apiKey: apiKey, region: .us, plan: plan, transport: transport)
        await recorded.receive(memory.records)
        let expectedURL = "https://api2.amplitude.com/2/httpapi"
        let request = try #require(transport.requests.first)
        let json = try #require(try JSONSerialization.jsonObject(with: request.body) as? [String: Any])
        let events = try #require(json["events"] as? [[String: Any]])
        let signedUp = try #require(events.first { $0["event_type"] as? String == "signed_up" })
        let properties = try #require(signedUp["event_properties"] as? [String: Any])
        let session = try #require(memory.records.first?.context[SessionKey.self])
        let expectedDeviceID = session.uuidString.lowercased()
        let expectedPlan = "pro"

        #expect(request.request.url?.absoluteString == expectedURL)
        #expect(transport.requests.count == 1)
        #expect(json["api_key"] as? String == apiKey)
        #expect(signedUp["device_id"] as? String == expectedDeviceID)
        #expect(signedUp["user_id"] == nil)
        #expect(properties["plan"] as? String == expectedPlan)
    }
}
