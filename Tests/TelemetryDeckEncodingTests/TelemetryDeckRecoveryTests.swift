import Crypto
import Destinations
import EventMacros
import Events
import Foundation
import HTTPDestinations
import HTTPTypes
import Instrumentation
import Persistence
import Sessions
import Synchronization
import TelemetryDeckEncoding
import Testing
import Trackers
import TrackingPlans

// A record a store recovers after a relaunch keeps its session (TRAF-122), so a resend of a
// record whose first send got no answer goes out under the identity of that send, and TelemetryDeck
// can tell it is a copy rather than a new user's event.

@Suite("TelemetryDeckBatchEncoder: recovered records", .timeLimit(.minutes(1)))
struct TelemetryDeckRecoveryTests {
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

    @Test("A record a SegmentStore recovers after the app ended while its request awaited an answer keeps the identity of its first send: its clientUser and sessionID")
    func recoveredRecordKeepsTheIdentityOfItsFirstSend() async throws {
        let tracked = Date(timeIntervalSince1970: 1_795_442_607)
        let directory = NSTemporaryDirectory() + "TelemetryDeckRecoveryTests-\(UUID().uuidString)"
        let copy = directory + "-copy"
        defer {
            try? FileManager.default.removeItem(atPath: directory)
            try? FileManager.default.removeItem(atPath: copy)
        }
        let endpoint = try #require(URL(string: "https://nom.telemetrydeck.com/v2/"))
        let sut = try TelemetryDeckBatchEncoder(appID: "B97579B6-FFB8-4AC5-AAA7-DA5796CC5DCE", testMode: false, plan: try TrackingPlan(schemas: [CheckoutStarted.schema]))
        let transport = GatedTransport()
        let tracker = Tracker(store: try SegmentStore(events: [CheckoutStarted.self], directory: .init(directory)), enrichers: [.sessions(kinds: [])], now: { tracked })
        let delivery = tracker.records.batch(strategy: .count(1)).deliver(to: HTTPDestination(endpoint: endpoint, instrument: NoOpInstrument(), transport: transport, encoder: sut))
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
        // clientUser is the SHA256 of the session's lowercase string, in lowercase hexadecimal.
        let clientUser = SHA256.hash(data: Data(session.uuidString.lowercased().utf8)).map { String(format: "%02x", $0) }.joined()
        func keys(_ body: Data) throws -> [String?] {
            let event = try #require((try JSONSerialization.jsonObject(with: body) as? [[String: Any]])?.first)
            return [event["clientUser"] as? String, event["sessionID"] as? String]
        }
        let expected: [String?] = [clientUser, session.uuidString.lowercased()]
        let actualFirst = try keys(firstBody)

        let actualRecovered = try keys(try #require(sut.requests(for: [recovered]).requests.first).body.body)

        #expect(recovered.isRedelivered)
        #expect(actualFirst == expected)
        #expect(actualRecovered == expected)
    }
}
