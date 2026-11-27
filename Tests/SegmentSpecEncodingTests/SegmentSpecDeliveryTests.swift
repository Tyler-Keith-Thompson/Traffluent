import Afluent
import Clocks
import DestinationTesting
import Destinations
import EventMacros
import Foundation
import HTTPDestinations
import HTTPTypes
import Instrumentation
import SegmentSpecEncoding
import Sessions
import Testing
import Trackers
import TrackingPlans

@Suite("HTTPDestination.segment, .rudderStack and .customerIO through a tracker", .timeLimit(.minutes(1)))
struct SegmentSpecDeliveryTests {
    @Event(name: "checkout_started")
    struct CheckoutStarted {
        var cartSize: Int
    }

    @Test("A tracker's batch reaches Segment as one request, each call's anonymousId the session and messageId the record's id")
    func trackerToEndpoint() async throws {
        let start = Date(timeIntervalSince1970: 1_795_442_607.5)
        let transport = ScriptedTransport([.status(.ok)])
        let segment = try HTTPDestination.segment(writeKey: "testwritekey", region: .us, plan: try TrackingPlan(schemas: [CheckoutStarted.schema]), transport: transport)
        let memory = InMemoryDestination()
        let tracker = Tracker(enrichers: [.sessions(kinds: [])], now: { start })
        let delivery = tracker.records.batch().deliver(to: segment, memory)
        let expectedRequestCount = 1
        let expectedTimestamp = "2026-11-23T14:03:27.500Z"

        tracker.track(CheckoutStarted(cartSize: 1))
        tracker.track(CheckoutStarted(cartSize: 2))
        await tracker.finish()
        try await delivery.execute()

        let session = try #require(memory.records.first?.context[SessionKey.self])
        let expectedIDs: [String?] = [session.uuidString.lowercased(), session.uuidString.lowercased()]
        let expectedMessageIDs: [String?] = memory.records.map { $0.id.uuidString.lowercased() }
        let request = try #require(transport.requests.first)
        let calls = try #require((try JSONSerialization.jsonObject(with: request.body) as? [String: Any])?["batch"] as? [[String: Any]])
        #expect(transport.requests.count == expectedRequestCount)
        #expect(calls.map { $0["anonymousId"] as? String } == expectedIDs)
        #expect(calls.map { $0["messageId"] as? String } == expectedMessageIDs)
        #expect(calls.map { $0["timestamp"] as? String } == [expectedTimestamp, expectedTimestamp])
        #expect(calls.allSatisfy { $0["userId"] == nil })
    }

    @Test("A request answered with 400, 401, 403, 404 or 413 is sent once, then dropped and reported as rejected, by every factory", arguments: [
        HTTPResponse.Status.badRequest, .unauthorized, .forbidden, .notFound, .contentTooLarge,
    ], [0, 1, 2])
    func rejectionDropped(status: HTTPResponse.Status, factory: Int) async throws {
        let transport = ScriptedTransport([.status(status), .status(.ok)])
        let plan = try TrackingPlan(schemas: [CheckoutStarted.schema])
        let sut = switch factory {
        case 0: try HTTPDestination.segment(writeKey: "testwritekey", region: .eu, plan: plan, transport: transport)
        case 1: try HTTPDestination.rudderStack(writeKey: "testwritekey", dataPlane: try #require(URL(string: "https://exampledataplane.rudderstack.com")), plan: plan, transport: transport)
        default: try HTTPDestination.customerIO(apiKey: "pk_eu_testkey", region: .eu, plan: plan, transport: transport)
        }
        let batch = [EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)]
        let expected = HTTPDropReport<SegmentSpecEncodingError>.rejected(status: status, recordIDs: [batch[0].id])
        let expectedRequestCount = 1

        await sut.receive(batch)

        var reports = sut.dropReports.makeAsyncIterator()
        let actual = await reports.next()
        #expect(actual == expected)
        #expect(transport.requests.count == expectedRequestCount)
    }

    @Test("A request answered with 429, 500, 502 or 503 is sent again after the backoff's wait, with the same body and fields, until it is taken", arguments: [
        HTTPResponse.Status.tooManyRequests, .internalServerError, .badGateway, .serviceUnavailable,
    ])
    func transientRetried(status: HTTPResponse.Status) async throws {
        let transport = ScriptedTransport([.status(status), .status(.ok)])
        let clock = TestClock()
        let sut = try HTTPDestination.customerIO(apiKey: "pk_us_testkey", region: .us, plan: try TrackingPlan(schemas: [CheckoutStarted.schema]), transport: transport, clock: clock)
        let batch = [EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)]
        let expectedRequestCount = 2
        let receiving = Task { await sut.receive(batch) }

        while (try? await clock.checkSuspension()) != nil {}
        await clock.advance(by: .seconds(1))
        await receiving.value

        let bodies = transport.requests.map(\.body)
        let authorizations = transport.requests.map { $0.request.headerFields[.authorization] }
        #expect(bodies.count == expectedRequestCount)
        #expect(Set(bodies).count == 1)
        #expect(Set(authorizations).count == 1)
    }

    @Test("A batch of semantic events isn't sent, and each record is reported as skipped with reservedEventName")
    func reservedBatchReported() async throws {
        struct UserDeleted: Event, Codable {
            static let name = "User Deleted"
        }
        let schema = EventSchema(name: "User Deleted", version: 1, consentCategory: .analytics, properties: [])
        let transport = ScriptedTransport([.status(.ok)])
        let sut = try HTTPDestination.segment(writeKey: "testwritekey", region: .us, plan: try TrackingPlan(schemas: [schema]), transport: transport)
        let batch = [EventRecord(event: UserDeleted(), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)]
        let expected = HTTPDropReport<SegmentSpecEncodingError>.skipped(SkippedRecord(recordID: batch[0].id, eventName: "User Deleted", schemaVersion: 1, reason: .reservedEventName(name: "User Deleted")))

        await sut.receive(batch)

        var reports = sut.dropReports.makeAsyncIterator()
        let actual = await reports.next()
        #expect(actual == expected)
        #expect(transport.requests.isEmpty)
    }
}
