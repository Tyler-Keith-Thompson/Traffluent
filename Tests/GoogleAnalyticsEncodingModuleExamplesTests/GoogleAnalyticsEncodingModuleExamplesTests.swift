// The example of the GoogleAnalyticsEncoding module's landing article
// (Sources/GoogleAnalyticsEncoding/GoogleAnalyticsEncoding.docc/GoogleAnalyticsEncoding.md),
// verbatim, so the article cannot drift from the code. The factory is compiled for macOS and Linux
// alone, as is the example.

#if os(macOS) || os(Linux)
import DestinationTesting
import EventMacros
import Foundation
import GoogleAnalyticsEncoding
import HTTPDestinations
import Testing
import TrackingPlans
import Traffluent

@Suite("GoogleAnalyticsEncoding module examples", .timeLimit(.minutes(1)))
struct GoogleAnalyticsEncodingModuleExamplesTests {
    @Event(name: "signed_up")
    struct SignedUp {
        var plan: String
    }

    @Test("Sending to Google Analytics")
    func sendingToGoogleAnalytics() async throws {
        let measurementID = "G-TEST000000"
        let apiSecret = "testapisecret"
        let memory = InMemoryDestination()
        let recording = Tracker(enrichers: [.sessions()])
        let recordingDelivery = recording.records.batch().deliver(to: memory)
        recording.track(SignedUp(plan: "pro"))
        await recording.finish()
        try await recordingDelivery.execute()

        let plan = try TrackingPlan()
        let googleAnalytics = try HTTPDestination.googleAnalytics(
            measurementID: measurementID,  // the web or data stream's, G-…
            apiSecret: apiSecret,  // from the server's configuration, never an app's
            region: .global,  // or .eu, to have Google collect the data in the EU
            plan: plan)
        // A server tracking its own events: its sessions are the server's.
        let tracker = Tracker(enrichers: [.sessions()])
        let delivery = tracker.records.batch().deliver(to: googleAnalytics)

        // Nothing is tracked through `tracker`, so nothing is sent and the example runs without a
        // network. The same factory, given a transport that records requests, is checked against
        // the recorded batch instead.
        await tracker.finish()
        try await delivery.execute()
        let transport = ScriptedTransport([.status(.noContent)])
        let recorded = try HTTPDestination.googleAnalytics(measurementID: measurementID, apiSecret: apiSecret, region: .global, plan: plan, transport: transport)
        await recorded.receive(memory.records)
        let expectedURL = "https://www.google-analytics.com/mp/collect?measurement_id=G-TEST000000&api_secret=testapisecret"
        let request = try #require(transport.requests.first)
        let body = try #require(try JSONSerialization.jsonObject(with: request.body) as? [String: Any])
        let events = try #require(body["events"] as? [[String: Any]])
        let signedUp = try #require(events.first { $0["name"] as? String == "signed_up" })
        let params = try #require(signedUp["params"] as? [String: Any])
        let session = try #require(memory.records.first?.context[SessionKey.self])
        let hex = session.uuidString.replacingOccurrences(of: "-", with: "")
        let expectedClientID = "\(UInt64(hex.prefix(16), radix: 16) ?? 0).\(UInt64(hex.suffix(16), radix: 16) ?? 0)"
        let expectedPlan = "pro"

        #expect(request.request.url?.absoluteString == expectedURL)
        #expect(transport.requests.count == 1)
        #expect(body["client_id"] as? String == expectedClientID)
        #expect(body["user_id"] == nil)
        #expect(params["plan"] as? String == expectedPlan)
    }
}
#endif
