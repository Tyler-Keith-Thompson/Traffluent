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

// Private: its events share their names with other events of this test target, and @Event
// leaves a private type's events out of the link check of names (DefiningEvents, Limits).
@Suite("HTTPDestination.aptabase through a tracker", .timeLimit(.minutes(1)))
private struct AptabaseDeliveryTests {
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

    // Aptabase answers 400 for more than 25 events or an event its model refuses. 417 and 419,
    // either side of the 418 it retries, are statuses it doesn't send, dropped as any other is.
    @Test("A request Aptabase answers with 400, 401, 403, 413, 417 or 419 is sent once, then dropped and reported as rejected", arguments: [
        HTTPResponse.Status.badRequest, .unauthorized, .forbidden, .contentTooLarge, HTTPResponse.Status(code: 417), HTTPResponse.Status(code: 419),
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

    // src/Extensions/ExceptionMiddleware.cs answers 418 for Kestrel's BadHttpRequestException, which
    // the minimum body data rate src/Program.cs sets (60 bytes a second after a 10-second grace
    // period) raises for a body that arrived too slowly (github.com/aptabase/aptabase at 89d36185,
    // read 2026-11-27).
    @Test("The encoder's transient statuses are 418 alone")
    func transientStatusesPinned() throws {
        // Read as HTTPDestination reads it, through the protocol, so a member of another type
        // than the requirement's couldn't pass.
        func transientStatuses<Encoder: BatchEncoder>(of encoder: Encoder.Type) -> Set<TransientStatus> {
            Encoder.transientStatuses
        }
        let expected: Set<TransientStatus> = [try TransientStatus(418)]

        let actual = transientStatuses(of: AptabaseBatchEncoder.self)

        #expect(actual == expected)
    }

    @Test("A request Aptabase answers with 418, for a body that arrived too slowly, is sent again after each of the backoff's waits on its clock, with the same body, and delivered on the next 2xx, with nothing reported")
    func slowUploadRetried() async throws {
        let tracked = Date(timeIntervalSince1970: 1_795_442_607)
        let transport = ScriptedTransport([.status(418), .status(418), .status(.ok), .status(.badRequest)])
        let clock = TestClock()
        let sut = try HTTPDestination.aptabase(appKey: "A-EU-1234567890", isDebug: false, plan: try TrackingPlan(schemas: [CheckoutStarted.schema]), transport: transport, backoff: ExponentialBackoff(jitter: .none), clock: clock, now: { tracked })
        let batch = [EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: tracked, sourceLocation: nil)]
        let later = [EventRecord(event: CheckoutStarted(cartSize: 2), timestamp: tracked, sourceLocation: nil)]
        // One request sent before the first wait, a second before the second: each waits the
        // backoff's 1 s, then 2 s.
        let expectedCountsBeforeEachWait = [1, 2]
        let expectedRequestCount = 4
        let expectedReport = HTTPDropReport<AptabaseEncodingError>.rejected(status: .badRequest, recordIDs: later.map(\.id))
        var countsBeforeEachWait: [Int] = []
        let receiving = Task { await sut.receive(batch) }

        for wait in [Duration.seconds(1), .seconds(2)] {
            while (try? await clock.checkSuspension()) != nil {}
            countsBeforeEachWait.append(transport.requests.count)
            await clock.advance(by: wait)
        }
        await receiving.value
        // The later batch's rejection is the first report, so the retried batch made none.
        await sut.receive(later)

        let bodies = transport.requests.map(\.body)
        #expect(countsBeforeEachWait == expectedCountsBeforeEachWait)
        #expect(bodies.count == expectedRequestCount)
        #expect(Set(bodies.prefix(3)).count == 1)
        var reports = sut.dropReports.makeAsyncIterator()
        let actual = await reports.next()
        #expect(actual == expectedReport)
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
