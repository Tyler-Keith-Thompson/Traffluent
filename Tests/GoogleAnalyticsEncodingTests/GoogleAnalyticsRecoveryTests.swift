// The module is compiled for macOS and Linux alone (Sources/GoogleAnalyticsEncoding).
#if os(macOS) || os(Linux)
import Destinations
import EventMacros
import Events
import Foundation
import GoogleAnalyticsEncoding
import HTTPDestinations
import HTTPTypes
import Instrumentation
import Persistence
import Sessions
import Synchronization
import Testing
import Trackers
import TrackingPlans

// A record a store recovers after a relaunch keeps its session (TRAF-122), so a resend of a
// record whose first send got no answer goes out under the identity of that send, and Google Analytics
// can tell it is a copy rather than a new user's event.

@Suite("GoogleAnalyticsBatchEncoder: recovered records", .timeLimit(.minutes(1)))
struct GoogleAnalyticsRecoveryTests {
    @Event(name: "checkout_started")
    struct CheckoutStarted {
        var cartSize: Int
    }

    /// Keeps each request's body and announces it on `arrivals`, then holds the request until
    /// the test finishes `opened`, and answers 200.
    final class GatedTransport: HTTPTransport {
        let bodies = Mutex<[Data]>([])
        let (arrivals, arrived) = AsyncStream.makeStream(of: Void.self)
        let (gate, opened) = AsyncStream.makeStream(of: Void.self)

        func send(_ request: HTTPRequest, body: Data) async throws(HTTPTransportError) -> HTTPResponse {
            bodies.withLock { $0.append(body) }
            arrived.yield()
            for await _ in gate {}
            return HTTPResponse(status: .ok)
        }
    }

    @Test("A record a SegmentStore recovers after the app ended while its request awaited an answer keeps the identity of its first send: its client_id and session_id")
    func recoveredRecordKeepsTheIdentityOfItsFirstSend() async throws {
        let tracked = Date(timeIntervalSince1970: 1_795_442_607)
        let directory = NSTemporaryDirectory() + "GoogleAnalyticsRecoveryTests-\(UUID().uuidString)"
        let copy = directory + "-copy"
        defer {
            try? FileManager.default.removeItem(atPath: directory)
            try? FileManager.default.removeItem(atPath: copy)
        }
        let endpoint = try #require(URL(string: "https://www.google-analytics.com/mp/collect"))
        let sut = GoogleAnalyticsBatchEncoder(plan: try TrackingPlan(schemas: [CheckoutStarted.schema]), now: { tracked })
        let transport = GatedTransport()
        let tracker = Tracker(store: try SegmentStore(events: [CheckoutStarted.self], directory: .init(directory)), enrichers: [.sessions(kinds: [])], now: { tracked })
        let delivery = tracker.records.batch(strategy: .count(1)).deliver(to: HTTPDestination(endpoint: endpoint, instrument: NoOpInstrument(), transport: transport, encoder: sut, now: { tracked }))
        let sending = Task { try await delivery.execute() }
        tracker.track(CheckoutStarted(cartSize: 1))
        for await _ in transport.arrivals { break }
        // The request is out and unanswered. The app ends here: the next launch opens the store on
        // what it left.
        try FileManager.default.copyItem(atPath: directory, toPath: copy)
        transport.opened.finish()
        await tracker.finish()
        try await sending.value
        let firstBody = try #require(transport.bodies.withLock { $0.first })
        let recovered = try #require(try SegmentStore(events: [CheckoutStarted.self], directory: .init(copy)).takeRecoveredRecords().first)
        let session = try #require(recovered.context[SessionKey.self])
        let sessionHigh = withUnsafeBytes(of: session.uuid) { $0.prefix(8).reduce(UInt64(0)) { $0 << 8 | UInt64($1) } }
        let sessionLow = withUnsafeBytes(of: session.uuid) { $0.suffix(8).reduce(UInt64(0)) { $0 << 8 | UInt64($1) } }
        // Google Analytics has no event identifier: the client and the session are what a copy shares.
        func keys(_ body: Data) throws -> [String?] {
            let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
            let event = try #require((object["events"] as? [[String: Any]])?.first)
            let params = try #require(event["params"] as? [String: Any])
            return [object["client_id"] as? String, params["session_id"].map { "\($0)" }]
        }
        let expected: [String?] = ["\(sessionHigh).\(sessionLow)", "\(sessionHigh >> 16)"]
        let actualFirst = try keys(firstBody)

        let actualRecovered = try keys(try #require(sut.requests(for: [recovered]).requests.first).body.body)

        #expect(recovered.isRedelivered)
        #expect(actualFirst == expected)
        #expect(actualRecovered == expected)
    }
}
#endif
