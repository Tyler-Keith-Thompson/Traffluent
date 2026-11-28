// The examples of the GoogleAnalyticsEncoding module's landing article
// (Sources/GoogleAnalyticsEncoding/GoogleAnalyticsEncoding.docc/GoogleAnalyticsEncoding.md),
// verbatim, so the article cannot drift from the code. The app's example sends to the collector and
// compiles everywhere; the factory is compiled for macOS and Linux alone, as is its example. The
// collector's environment block is shell, which no test compiles.

import EventMacros
import Foundation
import Testing
import TrackingPlans
import Traffluent

@Suite("GoogleAnalyticsEncoding module examples: through the collector", .timeLimit(.minutes(1)))
struct GoogleAnalyticsEncodingCollectorExamplesTests {
    // Not `signed_up`, which the other suite declares: the list-free TrackingPlan() discovers both.
    @Event(name: "checkout_started")
    struct CheckoutStarted {
        var items: Int
    }

    @Test("Getting an app's events to Google Analytics")
    func gettingAnAppsEventsToGoogleAnalytics() async throws {
        let collectorURL = try #require(URL(string: "https://collector.example.com/v1/batches"))
        let apiKey = "k3y"
        let memory = InMemoryDestination()
        let recording = Tracker(enrichers: [.sessions()])
        let recordingDelivery = recording.records.batch().deliver(to: memory)
        recording.track(CheckoutStarted(items: 2))
        await recording.finish()
        try await recordingDelivery.execute()

        let plan = try TrackingPlan()
        let collector = HTTPDestination(
            endpoint: collectorURL,  // https://collector.example.com/v1/batches
            headerFields: [.authorization: "Bearer \(apiKey)"],  // the collector's API key, not Google's
            encoder: CollectorBatchEncoder(plan: plan))
        // The sessions enricher gives each record the session the collector sends as its client_id.
        let tracker = Tracker(enrichers: [.sessions()])
        let delivery = tracker.records.batch().deliver(to: collector)

        // Nothing is tracked through `tracker`, so nothing is sent and the example runs without a
        // network. An encoder of the same plan is checked against the recorded batch instead: each
        // record carries the session the collector forwards as its client_id.
        await tracker.finish()
        try await delivery.execute()
        let encoded = CollectorBatchEncoder(plan: plan).batch(of: memory.records)
        let body = try #require(encoded.body)
        let json = try #require(try JSONSerialization.jsonObject(with: body.body) as? [String: Any])
        let records = try #require(json["records"] as? [[String: Any]])
        let context = try #require(records.first?["context"] as? [String: Any])
        let session = try #require(memory.records.first?.context[SessionKey.self])
        let expectedSession = session.uuidString
        let expectedCount = memory.records.count

        #expect(encoded.skippedRecords.isEmpty)
        #expect(records.count == expectedCount)
        #expect(context["session"] as? String == expectedSession)
    }
}

#if os(macOS) || os(Linux)
import DestinationTesting
import GoogleAnalyticsEncoding
import HTTPDestinations

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

    @Test("Sending from a server of your own")
    func sendingFromAServerOfYourOwn() async throws {
        let measurementID = "G-TEST000000"
        let apiSecret = "testapisecret"
        let memory = InMemoryDestination()
        let app = Tracker(enrichers: [.sessions()])
        let appDelivery = app.records.batch().deliver(to: memory)
        app.track(SignedUp(plan: "pro"))
        await app.finish()
        try await appDelivery.execute()
        let appBody = try #require(CollectorBatchEncoder(plan: try TrackingPlan()).batch(of: memory.records).body).body
        // An empty batch, so the verbatim destination, which has no test transport, sends nothing.
        let body = Data(#"{"records":[]}"#.utf8)

        let plan = try TrackingPlan()
        let decoder = try CollectorBatchDecoder(plan: plan)
        let googleAnalytics = try HTTPDestination.googleAnalytics(
            measurementID: measurementID,  // the web or data stream's, G-…
            apiSecret: apiSecret,  // from the server's configuration, never an app's
            region: .global,  // or .eu, to have Google collect the data in the EU
            plan: plan)

        // For each request the relay receives: its body, as the app's CollectorBatchEncoder wrote it.
        let batch = try decoder.batch(from: body)
        await googleAnalytics.receive(batch.records)

        // The same decoder, given the app's body, and the same factory, given a transport that
        // records requests: Google Analytics gets the app's session as the client_id.
        let transport = ScriptedTransport([.status(.noContent)])
        let recorded = try HTTPDestination.googleAnalytics(measurementID: measurementID, apiSecret: apiSecret, region: .global, plan: plan, transport: transport)
        let appBatch = try decoder.batch(from: appBody)
        await recorded.receive(appBatch.records)
        let request = try #require(transport.requests.first)
        let sent = try #require(try JSONSerialization.jsonObject(with: request.body) as? [String: Any])
        let events = try #require(sent["events"] as? [[String: Any]])
        let signedUp = try #require(events.first { $0["name"] as? String == "signed_up" })
        let params = try #require(signedUp["params"] as? [String: Any])
        let session = try #require(memory.records.first?.context[SessionKey.self])
        let hex = session.uuidString.replacingOccurrences(of: "-", with: "")
        let expectedClientID = "\(UInt64(hex.prefix(16), radix: 16) ?? 0).\(UInt64(hex.suffix(16), radix: 16) ?? 0)"
        let expectedPlan = "pro"

        #expect(batch.records.isEmpty)
        #expect(appBatch.undecodedRecords.isEmpty)
        #expect(appBatch.records.map(\.id) == memory.records.map(\.id))
        #expect(transport.requests.count == 1)
        #expect(sent["client_id"] as? String == expectedClientID)
        #expect(params["plan"] as? String == expectedPlan)
    }
}
#endif
