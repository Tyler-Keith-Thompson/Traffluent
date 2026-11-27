// The factory is compiled for macOS and Linux alone (HTTPDestination+GoogleAnalytics.swift).
#if os(macOS) || os(Linux)
import Afluent
import Clocks
import DestinationTesting
import Destinations
import EventMacros
import Foundation
import GoogleAnalyticsEncoding
import HTTPDestinations
import HTTPTypes
import Instrumentation
import Sessions
import Testing
import Trackers
import TrackingPlans

@Suite("HTTPDestination.googleAnalytics through a tracker", .timeLimit(.minutes(1)))
struct GoogleAnalyticsDeliveryTests {
    @Event(name: "checkout_started")
    struct CheckoutStarted {
        var cartSize: Int
    }

    @Test("A tracker's batch reaches the endpoint as one request, its client_id the session and each event's session_id the session's start")
    func trackerToEndpoint() async throws {
        let start = Date(timeIntervalSince1970: 1_795_442_607.5)
        let transport = ScriptedTransport([.status(.noContent)])
        let googleAnalytics = try HTTPDestination.googleAnalytics(
            measurementID: "G-TEST000000",
            apiSecret: "testapisecret",
            region: .global,
            plan: try TrackingPlan(schemas: [CheckoutStarted.schema]),
            transport: transport,
            now: { start }
        )
        let memory = InMemoryDestination()
        let tracker = Tracker(enrichers: [.sessions(kinds: [])], now: { start })
        let delivery = tracker.records.batch().deliver(to: googleAnalytics, memory)
        let expectedRequestCount = 1
        let expectedMicros: Int64 = 1_795_442_607_500_000

        tracker.track(CheckoutStarted(cartSize: 1))
        tracker.track(CheckoutStarted(cartSize: 2))
        await tracker.finish()
        try await delivery.execute()

        let session = try #require(memory.records.first?.context[SessionKey.self])
        let hex = session.uuidString.replacingOccurrences(of: "-", with: "")
        let expectedClientID = "\(UInt64(hex.prefix(16), radix: 16) ?? 0).\(UInt64(hex.suffix(16), radix: 16) ?? 0)"
        let expectedSessionID = Int64(hex.prefix(12), radix: 16)
        let request = try #require(transport.requests.first)
        let body = try #require(try JSONSerialization.jsonObject(with: request.body) as? [String: Any])
        let events = try #require(body["events"] as? [[String: Any]])
        let actualSessionIDs = events.map { (($0["params"] as? [String: Any])?["session_id"] as? NSNumber)?.int64Value }
        let actualMicros = events.map { ($0["timestamp_micros"] as? NSNumber)?.int64Value }
        #expect(transport.requests.count == expectedRequestCount)
        #expect(body["client_id"] as? String == expectedClientID)
        #expect(actualSessionIDs == [expectedSessionID, expectedSessionID])
        #expect(actualMicros == [expectedMicros, expectedMicros])
    }

    @Test("A request answered with 400, 401, 403 or 413 is sent once, then dropped and reported as rejected", arguments: [
        HTTPResponse.Status.badRequest, .unauthorized, .forbidden, .contentTooLarge,
    ])
    func rejectionDropped(status: HTTPResponse.Status) async throws {
        let transport = ScriptedTransport([.status(status), .status(.noContent)])
        let sut = try HTTPDestination.googleAnalytics(measurementID: "G-TEST000000", apiSecret: "testapisecret", region: .eu, plan: try TrackingPlan(schemas: [CheckoutStarted.schema]), transport: transport, now: { Date(timeIntervalSince1970: 1_795_442_607) })
        let batch = [EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)]
        let expected = HTTPDropReport<GoogleAnalyticsEncodingError>.rejected(status: status, recordIDs: [batch[0].id])
        let expectedRequestCount = 1

        await sut.receive(batch)

        var reports = sut.dropReports.makeAsyncIterator()
        let actual = await reports.next()
        #expect(actual == expected)
        #expect(transport.requests.count == expectedRequestCount)
    }

    @Test("A request answered with 408, 429, 502 or 503 is sent again after the backoff's wait, with the same body, until it is taken", arguments: [
        HTTPResponse.Status.requestTimeout, .tooManyRequests, .badGateway, .serviceUnavailable,
    ])
    func transientRetried(status: HTTPResponse.Status) async throws {
        let transport = ScriptedTransport([.status(status), .status(.noContent)])
        let clock = TestClock()
        let sut = try HTTPDestination.googleAnalytics(measurementID: "G-TEST000000", apiSecret: "testapisecret", region: .global, plan: try TrackingPlan(schemas: [CheckoutStarted.schema]), transport: transport, clock: clock, now: { Date(timeIntervalSince1970: 1_795_442_607) })
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

    @Test("A batch of events Google Analytics reserves isn't sent, and each record is reported as skipped with reservedEventName")
    func reservedBatchReported() async throws {
        struct SessionStart: Event, Codable {
            static let name = "session_start"
        }
        let sessionStart = EventSchema(name: "session_start", version: 1, consentCategory: .analytics, properties: [])
        let transport = ScriptedTransport([.status(.noContent)])
        let sut = try HTTPDestination.googleAnalytics(measurementID: "G-TEST000000", apiSecret: "testapisecret", region: .global, plan: try TrackingPlan(schemas: [sessionStart]), transport: transport, now: { Date(timeIntervalSince1970: 1_795_442_607) })
        let batch = [EventRecord(event: SessionStart(), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)]
        let expected = HTTPDropReport<GoogleAnalyticsEncodingError>.skipped(SkippedRecord(recordID: batch[0].id, eventName: "session_start", schemaVersion: 1, reason: .reservedEventName(name: "session_start")))

        await sut.receive(batch)

        var reports = sut.dropReports.makeAsyncIterator()
        let actual = await reports.next()
        #expect(actual == expected)
        #expect(transport.requests.isEmpty)
    }

    @Test("A record more than 72 hours older than the destination's clock isn't sent, and is reported as skipped with timestampOutsideWindow")
    func staleRecordReported() async throws {
        let transport = ScriptedTransport([.status(.noContent)])
        let sut = try HTTPDestination.googleAnalytics(measurementID: "G-TEST000000", apiSecret: "testapisecret", region: .global, plan: try TrackingPlan(schemas: [CheckoutStarted.schema]), transport: transport, now: { Date(timeIntervalSince1970: 1_795_442_607 + 259_201) })
        let batch = [EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)]
        let expected = HTTPDropReport<GoogleAnalyticsEncodingError>.skipped(SkippedRecord(recordID: batch[0].id, eventName: "checkout_started", schemaVersion: 1, reason: .timestampOutsideWindow))

        await sut.receive(batch)

        var reports = sut.dropReports.makeAsyncIterator()
        let actual = await reports.next()
        #expect(actual == expected)
        #expect(transport.requests.isEmpty)
    }
}
#endif
