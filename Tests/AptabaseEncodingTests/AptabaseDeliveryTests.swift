import Afluent
import AptabaseEncoding
import Clocks
import DestinationTesting
import Destinations
import EventMacros
import Foundation
import HTTPDestinations
import HTTPTypes
import Instrumentation
import Sessions
import Testing
import Trackers
import TrackingPlans

@Suite("HTTPDestination.aptabase through a tracker", .timeLimit(.minutes(1)))
struct AptabaseDeliveryTests {
    @Event(name: "checkout_started")
    struct CheckoutStarted {
        var cartSize: Int
    }

    @Test("A tracker's batch reaches the endpoint as one request, each event's sessionId the session")
    func trackerToEndpoint() async throws {
        let start = Date(timeIntervalSince1970: 1_795_442_607.5)
        let transport = ScriptedTransport([.status(.ok)])
        let aptabase = try HTTPDestination.aptabase(appKey: "A-EU-1234567890", isDebug: false, plan: try TrackingPlan(schemas: [CheckoutStarted.schema]), transport: transport, now: { start })
        let memory = InMemoryDestination()
        let tracker = Tracker(enrichers: [.sessions(kinds: [])], now: { start })
        let delivery = tracker.records.batch().deliver(to: aptabase, memory)
        let expectedRequestCount = 1
        let expectedTimestamp = "2026-11-23T14:03:27.500Z"

        tracker.track(CheckoutStarted(cartSize: 1))
        tracker.track(CheckoutStarted(cartSize: 2))
        await tracker.finish()
        try await delivery.execute()

        let session = try #require(memory.records.first?.context[SessionKey.self])
        let expectedSessions: [String?] = [session.uuidString.lowercased(), session.uuidString.lowercased()]
        let request = try #require(transport.requests.first)
        let events = try #require(try JSONSerialization.jsonObject(with: request.body) as? [[String: Any]])
        #expect(transport.requests.count == expectedRequestCount)
        #expect(events.map { $0["sessionId"] as? String } == expectedSessions)
        #expect(events.map { $0["eventName"] as? String } == ["checkout_started", "checkout_started"])
        #expect(events.map { $0["timestamp"] as? String } == [expectedTimestamp, expectedTimestamp])
    }

    @Test("The factory's isDebug reaches every event's systemProps", arguments: [true, false])
    func factoryIsDebug(isDebug: Bool) async throws {
        let tracked = Date(timeIntervalSince1970: 1_795_442_607)
        let transport = ScriptedTransport([.status(.ok)])
        let sut = try HTTPDestination.aptabase(appKey: "A-US-1234567890", isDebug: isDebug, plan: try TrackingPlan(schemas: [CheckoutStarted.schema]), transport: transport, now: { tracked })
        let batch = (1 ... 2).map { EventRecord(event: CheckoutStarted(cartSize: $0), timestamp: tracked, sourceLocation: nil) }
        let expected: [Bool?] = [isDebug, isDebug]

        await sut.receive(batch)

        let request = try #require(transport.requests.first)
        let events = try #require(try JSONSerialization.jsonObject(with: request.body) as? [[String: Any]])
        #expect(events.map { ($0["systemProps"] as? [String: Any])?["isDebug"] as? Bool } == expected)
    }

    @Test("A record sent again, as a store redelivers it, has the same body, which Aptabase counts again, as it keeps no event's ID")
    func redeliveredRecordKeepsItsBody() async throws {
        let tracked = Date(timeIntervalSince1970: 1_795_442_607)
        let transport = ScriptedTransport([.status(.ok), .status(.ok)])
        let sut = try HTTPDestination.aptabase(appKey: "A-EU-1234567890", isDebug: false, plan: try TrackingPlan(schemas: [CheckoutStarted.schema]), transport: transport, now: { tracked })
        let record = EventRecord(id: UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!, event: CheckoutStarted(cartSize: 1), timestamp: tracked, sourceLocation: nil)
        let redelivered = EventRecord(id: record.id, event: CheckoutStarted(cartSize: 1), timestamp: record.timestamp, sourceLocation: nil, isRedelivered: true)
        let expectedRequestCount = 2

        await sut.receive([record])
        await sut.receive([redelivered])

        let bodies = transport.requests.map(\.body)
        #expect(bodies.count == expectedRequestCount)
        #expect(Set(bodies).count == 1)
    }

    // Aptabase answers 400 for more than 25 events or an event its model refuses; ExceptionMiddleware
    // answers 418 when the body arrived too slowly: Kestrel's BadHttpRequestException (408) under
    // the minimum body data rate src/Program.cs sets, 60 bytes a second after a 10-second grace
    // period, or a request the client aborted (github.com/aptabase/aptabase at 89d36185,
    // src/Extensions/ExceptionMiddleware.cs, read 2026-11-27). HTTPDestination drops a 418 as it
    // drops any status it doesn't retry.
    @Test("A request Aptabase answers with 400, 401, 403, 413 or 418 is sent once, then dropped and reported as rejected", arguments: [
        HTTPResponse.Status.badRequest, .unauthorized, .forbidden, .contentTooLarge, HTTPResponse.Status(code: 418),
    ])
    func rejectionDropped(status: HTTPResponse.Status) async throws {
        let tracked = Date(timeIntervalSince1970: 1_795_442_607)
        let transport = ScriptedTransport([.status(status), .status(.ok)])
        let sut = try HTTPDestination.aptabase(appKey: "A-US-1234567890", isDebug: false, plan: try TrackingPlan(schemas: [CheckoutStarted.schema]), transport: transport, now: { tracked })
        let batch = [EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: tracked, sourceLocation: nil)]
        let expected = HTTPDropReport<AptabaseEncodingError>.rejected(status: status, recordIDs: [batch[0].id])
        let expectedRequestCount = 1

        await sut.receive(batch)

        var reports = sut.dropReports.makeAsyncIterator()
        let actual = await reports.next()
        #expect(actual == expected)
        #expect(transport.requests.count == expectedRequestCount)
    }

    // src/Program.cs: the EventIngestion policy takes 20 requests a second per client IP and
    // answers 429 past it.
    @Test("A request Aptabase answers with 429, past its rate limit, or 500, 502 or 503, is sent again after the backoff's wait, with the same body, until it is taken", arguments: [
        HTTPResponse.Status.tooManyRequests, .internalServerError, .badGateway, .serviceUnavailable,
    ])
    func transientRetried(status: HTTPResponse.Status) async throws {
        let tracked = Date(timeIntervalSince1970: 1_795_442_607)
        let transport = ScriptedTransport([.status(status), .status(.ok)])
        let clock = TestClock()
        let sut = try HTTPDestination.aptabase(appKey: "A-EU-1234567890", isDebug: false, plan: try TrackingPlan(schemas: [CheckoutStarted.schema]), transport: transport, clock: clock, now: { tracked })
        let batch = [EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: tracked, sourceLocation: nil)]
        let expectedRequestCount = 2
        let receiving = Task { await sut.receive(batch) }

        while (try? await clock.checkSuspension()) != nil {}
        await clock.advance(by: .seconds(1))
        await receiving.value

        let bodies = transport.requests.map(\.body)
        #expect(bodies.count == expectedRequestCount)
        #expect(Set(bodies).count == 1)
    }

    @Test("A batch of records Aptabase can't take isn't sent, and each record is reported as skipped")
    func skippedBatchReported() async throws {
        let tracked = Date(timeIntervalSince1970: 1_795_442_607)
        let transport = ScriptedTransport([.status(.ok)])
        let sut = try HTTPDestination.aptabase(appKey: "A-EU-1234567890", isDebug: false, plan: try TrackingPlan(schemas: [CheckoutStarted.schema]), transport: transport, now: { tracked.addingTimeInterval(82_801) })
        let batch = [EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: tracked, sourceLocation: nil)]
        let expected = HTTPDropReport<AptabaseEncodingError>.skipped(SkippedRecord(recordID: batch[0].id, eventName: "checkout_started", schemaVersion: 1, reason: .timestampOutsideWindow))

        await sut.receive(batch)

        var reports = sut.dropReports.makeAsyncIterator()
        let actual = await reports.next()
        #expect(actual == expected)
        #expect(transport.requests.isEmpty)
    }
}
