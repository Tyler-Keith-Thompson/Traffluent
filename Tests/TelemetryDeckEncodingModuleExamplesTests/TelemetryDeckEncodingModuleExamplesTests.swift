// The example of the TelemetryDeckEncoding module's landing article
// (Sources/TelemetryDeckEncoding/TelemetryDeckEncoding.docc/TelemetryDeckEncoding.md), verbatim, so
// the article cannot drift from the code.

import DestinationTesting
import EventMacros
import Foundation
import HTTPDestinations
import TelemetryDeckEncoding
import Testing
import TrackingPlans
import Traffluent

@Suite("TelemetryDeckEncoding module examples", .timeLimit(.minutes(1)))
struct TelemetryDeckEncodingModuleExamplesTests {
    @Event(name: "signed_up")
    struct SignedUp {
        var plan: String
    }

    @Test("Sending to TelemetryDeck")
    func sendingToTelemetryDeck() async throws {
        let appID = "B97579B6-FFB8-4AC5-AAA7-DA5796CC5DCE"
        let memory = InMemoryDestination()
        let recording = Tracker(enrichers: [.sessions()])
        let recordingDelivery = recording.records.batch().deliver(to: memory)
        recording.track(SignedUp(plan: "pro"))
        await recording.finish()
        try await recordingDelivery.execute()

        let plan = try TrackingPlan()
        let telemetryDeck = try HTTPDestination.telemetryDeck(
            appID: appID,  // from the app's settings in the TelemetryDeck dashboard
            namespace: "com.example",  // your organization's namespace
            testMode: false,  // true for builds whose signals only Test Mode should show
            plan: plan)
        let tracker = Tracker(enrichers: [.sessions()])
        let delivery = tracker.records.batch().deliver(to: telemetryDeck)

        // Nothing is tracked through `tracker`, so nothing is sent and the example runs without a
        // network. The same factory, given a transport that records requests, is checked against
        // the recorded batch instead.
        await tracker.finish()
        try await delivery.execute()
        let transport = ScriptedTransport([.status(.ok)])
        let recorded = try HTTPDestination.telemetryDeck(appID: appID, namespace: "com.example", testMode: false, plan: plan, transport: transport)
        await recorded.receive(memory.records)
        let expectedURL = "https://nom.telemetrydeck.com/v3/com.example/"
        let request = try #require(transport.requests.first)
        let signals = try #require(try JSONSerialization.jsonObject(with: request.body) as? [[String: Any]])
        let signedUp = try #require(signals.first { $0["type"] as? String == "signed_up" })
        let session = try #require(memory.records.first?.context[SessionKey.self])
        let expectedSession = session.uuidString.lowercased()
        // The hash itself is pinned in TelemetryDeckEncodingTests; here, it is a SHA-256 in hex.
        let clientUser = try #require(signedUp["clientUser"] as? String)
        let expectedClientUserLength = 64
        let expectedPlan = "pro"

        #expect(request.request.url?.absoluteString == expectedURL)
        #expect(signedUp["sessionID"] as? String == expectedSession)
        #expect(clientUser.count == expectedClientUserLength)
        #expect(clientUser.allSatisfy { $0.isHexDigit && !$0.isUppercase })
        #expect(signedUp["appID"] as? String == appID)
        #expect(signedUp["isTestMode"] as? String == "false")
        #expect(signedUp["plan"] as? String == expectedPlan)
    }
}
