// The example of the MatomoEncoding module's landing article
// (Sources/MatomoEncoding/MatomoEncoding.docc/MatomoEncoding.md), verbatim, so the article cannot
// drift from the code.

import DestinationTesting
import EventMacros
import Foundation
import HTTPDestinations
import MatomoEncoding
import Testing
import TrackingPlans
import Traffluent

@Suite("MatomoEncoding module examples", .timeLimit(.minutes(1)))
struct MatomoEncodingModuleExamplesTests {
    @Event(name: "signed_up")
    struct SignedUp {
        var plan: String
    }

    @Test("Sending to Matomo")
    func sendingToMatomo() async throws {
        let url = try #require(URL(string: "https://analytics.example.com"))
        let memory = InMemoryDestination()
        let recording = Tracker(enrichers: [.sessions()])
        let recordingDelivery = recording.records.batch().deliver(to: memory)
        recording.track(SignedUp(plan: "pro"))
        await recording.finish()
        try await recordingDelivery.execute()

        let plan = try TrackingPlan()
        let matomo = try HTTPDestination.matomo(
            url: url,  // where Matomo is installed: https://analytics.example.com
            siteID: 3,  // the app's site in Matomo
            dimensions: ["plan": 1],  // custom dimensions made in Matomo
            category: "Shop",  // each event's category
            plan: plan)
        let tracker = Tracker(enrichers: [.sessions()])
        let delivery = tracker.records.batch().deliver(to: matomo)

        // Nothing is tracked through `tracker`, so nothing is sent and the example runs without a
        // network. The same factory, given a transport that records requests, is checked against
        // the recorded batch instead.
        await tracker.finish()
        try await delivery.execute()
        let transport = ScriptedTransport([.status(.ok)])
        let recorded = try HTTPDestination.matomo(url: url, siteID: 3, dimensions: ["plan": 1], category: "Shop", plan: plan, transport: transport)
        await recorded.receive(memory.records)
        let expectedURL = "https://analytics.example.com/matomo.php"
        let request = try #require(transport.requests.first)
        let body = try #require(try JSONSerialization.jsonObject(with: request.body) as? [String: [String]])
        let signedUp = try #require(body["requests"]?.first { $0.contains("&e_a=signed_up&") })
        let session = try #require(memory.records.first { $0.name == "signed_up" }?.context[SessionKey.self])
        let expectedVisitor = String(session.uuidString.lowercased().filter { $0 != "-" }.suffix(16))

        #expect(request.request.url?.absoluteString == expectedURL)
        #expect(signedUp.hasPrefix("?idsite=3&rec=1&apiv=1&_id=\(expectedVisitor)&cdt="))
        #expect(signedUp.contains("&ca=1&e_c=Shop&e_a=signed_up&"))
        #expect(signedUp.hasSuffix("&dimension1=pro"))
    }
}
