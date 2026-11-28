import Afluent
import Clocks
import DestinationTesting
import Destinations
import EventMacros
import Foundation
import HeapEncoding
import HTTPDestinations
import HTTPTypes
import Instrumentation
import Sessions
import Testing
import Trackers
import TrackingPlans

// Private: its events share their names with other events of this test target, and @Event
// leaves a private type's events out of the link check of names (DefiningEvents, Limits).
@Suite("HTTPDestination.heap through a tracker", .timeLimit(.minutes(1)))
private struct HeapDeliveryTests {
    @Event(name: "checkout_started")
    struct CheckoutStarted {
        var cartSize: Int
    }

    @Test("A tracker's batch reaches the endpoint as one request, each event's identity the session and its idempotency_key its record's id")
    func trackerToEndpoint() async throws {
        let start = Date(timeIntervalSince1970: 1_795_442_607.5)
        let transport = ScriptedTransport([.status(.ok)])
        let heap = try HTTPDestination.heap(appID: "12343283", region: .us, plan: try TrackingPlan(schemas: [CheckoutStarted.schema]), transport: transport)
        let memory = InMemoryDestination()
        let tracker = Tracker(enrichers: [.sessions(kinds: [])], now: { start })
        let delivery = tracker.records.batch().deliver(to: heap, memory)
        let expectedRequestCount = 1
        let expectedTimestamp = "2026-11-23T14:03:27.500Z"

        tracker.track(CheckoutStarted(cartSize: 1))
        tracker.track(CheckoutStarted(cartSize: 2))
        await tracker.finish()
        try await delivery.execute()

        let session = try #require(memory.records.first?.context[SessionKey.self])
        let expectedIdentities: [String?] = [session.uuidString.lowercased(), session.uuidString.lowercased()]
        let expectedKeys: [String?] = memory.records.map { $0.id.uuidString.lowercased() }
        let request = try #require(transport.requests.first)
        let body = try #require(try JSONSerialization.jsonObject(with: request.body) as? [String: Any])
        let events = try #require(body["events"] as? [[String: Any]])
        #expect(transport.requests.count == expectedRequestCount)
        #expect(body["app_id"] as? String == "12343283")
        #expect(events.map { $0["identity"] as? String } == expectedIdentities)
        #expect(events.map { $0["idempotency_key"] as? String } == expectedKeys)
        #expect(events.map { $0["timestamp"] as? String } == [expectedTimestamp, expectedTimestamp])
    }

    @Test("A record sent again under the same identity, as a store redelivers it, has the same body, so Heap stores it once by its idempotency_key within that identity")
    func redeliveredRecordKeepsItsKey() async throws {
        let transport = ScriptedTransport([.status(.ok), .status(.ok)])
        let sut = try HTTPDestination.heap(appID: "12343283", region: .us, plan: try TrackingPlan(schemas: [CheckoutStarted.schema]), transport: transport)
        let record = EventRecord(id: UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!, event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let redelivered = EventRecord(id: record.id, event: CheckoutStarted(cartSize: 1), timestamp: record.timestamp, sourceLocation: nil, isRedelivered: true)
        let expectedRequestCount = 2

        await sut.receive([record])
        await sut.receive([redelivered])

        let bodies = transport.requests.map(\.body)
        #expect(bodies.count == expectedRequestCount)
        #expect(Set(bodies).count == 1)
    }

    @Test("A request Heap answers with 400, 401, 403 or 413 is sent once, then dropped and reported as rejected", arguments: [
        HTTPResponse.Status.badRequest, .unauthorized, .forbidden, .contentTooLarge,
    ])
    func rejectionDropped(status: HTTPResponse.Status) async throws {
        let transport = ScriptedTransport([.status(status), .status(.ok)])
        let sut = try HTTPDestination.heap(appID: "12343283", region: .eu, plan: try TrackingPlan(schemas: [CheckoutStarted.schema]), transport: transport)
        let batch = [EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)]
        let expected = HTTPDropReport<HeapEncodingError>.rejected(status: status, recordIDs: [batch[0].id])
        let expectedRequestCount = 1

        await sut.receive(batch)

        var reports = sut.dropReports.makeAsyncIterator()
        let actual = await reports.next()
        #expect(actual == expected)
        #expect(transport.requests.count == expectedRequestCount)
    }

    @Test("A request Heap answers with 429, past its rate limits, or 502 or 503, is sent again after the backoff's wait, with the same body, until it is taken", arguments: [
        HTTPResponse.Status.tooManyRequests, .badGateway, .serviceUnavailable,
    ])
    func transientRetried(status: HTTPResponse.Status) async throws {
        let transport = ScriptedTransport([.status(status), .status(.ok)])
        let clock = TestClock()
        let sut = try HTTPDestination.heap(appID: "12343283", region: .us, plan: try TrackingPlan(schemas: [CheckoutStarted.schema]), transport: transport, backoff: ExponentialBackoff(jitter: .none), clock: clock)
        let batch = [EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)]
        let expectedRequestCount = 2
        let receiving = Task { await sut.receive(batch) }

        while (try? await clock.checkSuspension()) != nil {}
        await clock.advance(by: .seconds(1))
        await receiving.value

        let bodies = transport.requests.map(\.body)
        #expect(bodies.count == expectedRequestCount)
        #expect(Set(bodies).count == 1)
    }

    @Test("A batch of records Heap can't take isn't sent, and each record is reported as skipped")
    func skippedBatchReported() async throws {
        struct Viewed: Event, Codable {
            static let name = "viewed"
            var screen_name: String
        }
        let viewed = EventSchema(name: "viewed", version: 1, consentCategory: .analytics, properties: [EventSchema.Property(name: "screen_name", typeName: "String", isOptional: false)])
        let transport = ScriptedTransport([.status(.ok)])
        let sut = try HTTPDestination.heap(appID: "12343283", region: .us, plan: try TrackingPlan(schemas: [viewed]), transport: transport)
        let batch = [EventRecord(event: Viewed(screen_name: "Cart"), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)]
        let expected = HTTPDropReport<HeapEncodingError>.skipped(SkippedRecord(recordID: batch[0].id, eventName: "viewed", schemaVersion: 1, reason: .reservedPropertyName(event: "viewed", property: "screen_name")))

        await sut.receive(batch)

        var reports = sut.dropReports.makeAsyncIterator()
        let actual = await reports.next()
        #expect(actual == expected)
        #expect(transport.requests.isEmpty)
    }
}
