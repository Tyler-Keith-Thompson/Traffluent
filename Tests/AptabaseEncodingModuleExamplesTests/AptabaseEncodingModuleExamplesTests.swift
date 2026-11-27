// The example of the AptabaseEncoding module's landing article
// (Sources/AptabaseEncoding/AptabaseEncoding.docc/AptabaseEncoding.md), verbatim, so the article
// cannot drift from the code.

import AptabaseEncoding
import DestinationTesting
import EventMacros
import Foundation
import HTTPDestinations
import HTTPTypes
import Testing
import TrackingPlans
import Traffluent

@Suite("AptabaseEncoding module examples", .timeLimit(.minutes(1)))
struct AptabaseEncodingModuleExamplesTests {
    @Event(name: "signed_up")
    struct SignedUp {
        var plan: String
    }

    @Test("Sending to Aptabase")
    func sendingToAptabase() async throws {
        let appKey = "A-EU-1234567890"
        let memory = InMemoryDestination()
        let recording = Tracker(enrichers: [.sessions(), .application(), .device(), .operatingSystem(), .locale()])
        let recordingDelivery = recording.records.batch().deliver(to: memory)
        recording.track(SignedUp(plan: "pro"))
        await recording.finish()
        try await recordingDelivery.execute()

        let plan = try TrackingPlan()
        let aptabase = try HTTPDestination.aptabase(
            appKey: appKey,  // from the app's Instructions page: A-EU-…, A-US-… or A-SH-…
            isDebug: false,  // true for builds whose events only Debug mode should show
            plan: plan)
        let tracker = Tracker(enrichers: [.sessions(), .application(), .device(), .operatingSystem(), .locale()])
        let delivery = tracker.records.batch().deliver(to: aptabase)

        // Nothing is tracked through `tracker`, so nothing is sent and the example runs without a
        // network. The same factory, given a transport that records requests, is checked against
        // the recorded batch instead.
        await tracker.finish()
        try await delivery.execute()
        let transport = ScriptedTransport([.status(.ok)])
        let sut = try HTTPDestination.aptabase(appKey: appKey, isDebug: false, plan: plan, transport: transport)
        let record = try #require(memory.records.first { $0.name == "signed_up" })
        let session = try #require(record.context[SessionKey.self])
        let appKeyField = try #require(HTTPField.Name("App-Key"))
        let expectedURL = "https://eu.aptabase.com/api/v0/events"
        let expectedSession = session.uuidString.lowercased()
        let expectedProperties = ["plan": "pro"]

        await sut.receive(memory.records)

        let request = try #require(transport.requests.first)
        let events = try #require(try JSONSerialization.jsonObject(with: request.body) as? [[String: Any]])
        let signedUp = try #require(events.first { $0["eventName"] as? String == "signed_up" })
        let system = try #require(signedUp["systemProps"] as? [String: Any])
        #expect(request.request.url?.absoluteString == expectedURL)
        #expect(request.request.headerFields[appKeyField] == appKey)
        #expect(signedUp["sessionId"] as? String == expectedSession)
        #expect(signedUp["props"] as? [String: String] == expectedProperties)
        #expect(system["osName"] is String)
        #expect(system["sdkVersion"] as? String == "Traffluent")
    }
}
