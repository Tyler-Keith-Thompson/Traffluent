// The module is compiled for macOS and Linux alone (Sources/GoogleAnalyticsEncoding).
#if os(macOS) || os(Linux)
import Clocks
import DestinationTesting
import EventMacros
import Foundation
import GoogleAnalyticsEncoding
import HTTPDestinations
import Instrumentation
import PropertyJSON
import Sessions
import Testing
import TrackingPlans

// Private: its events share their names with other events of this test target, and @Event
// leaves a private type's events out of the link check of names (DefiningEvents, Limits).
@Suite("GoogleAnalyticsBatchEncoder: request deadlines", .timeLimit(.minutes(1)))
private struct GoogleAnalyticsDeadlineTests {
    @Event(name: "searched")
    struct Searched {
        var query: String
    }

    @Test("Each request's deadline is 71 hours after the earliest of its records was tracked, per client and per request a client's records are split into")
    func deadlinePerRequest() throws {
        let limit = try BatchLimit(maximumRecordCount: 2, maximumByteCount: .max, maximumRecordByteCount: .max)
        let sut = GoogleAnalyticsBatchEncoder(plan: try TrackingPlan(schemas: [Searched.schema]), limit: limit, now: { Date(timeIntervalSince1970: 1_795_442_700) })
        var context = ServiceContext.topLevel
        context[SessionKey.self] = UUID(uuidString: "01A208B7-E840-7A3E-8B4D-5C6E7F801234")!
        // The session's records of 610 and 600 share a request, its record of 620 is a second, and
        // the sessionless record of 605 is a client, and a request, of its own.
        let batch = [
            EventRecord(event: Searched(query: "a"), timestamp: Date(timeIntervalSince1970: 1_795_442_610), sourceLocation: nil, context: context),
            EventRecord(event: Searched(query: "b"), timestamp: Date(timeIntervalSince1970: 1_795_442_605), sourceLocation: nil),
            EventRecord(event: Searched(query: "c"), timestamp: Date(timeIntervalSince1970: 1_795_442_600), sourceLocation: nil, context: context),
            EventRecord(event: Searched(query: "d"), timestamp: Date(timeIntervalSince1970: 1_795_442_620), sourceLocation: nil, context: context),
        ]
        let hours71: TimeInterval = 255_600
        let expectedIDs = [[batch[0].id, batch[2].id], [batch[3].id], [batch[1].id]]
        let expectedDeadlines: [Date?] = [1_795_442_600 + hours71, 1_795_442_620 + hours71, 1_795_442_605 + hours71].map { Date(timeIntervalSince1970: $0) }

        let actual = sut.requests(for: batch).requests

        #expect(actual.map(\.recordIDs) == expectedIDs)
        #expect(actual.map(\.deadline) == expectedDeadlines)
    }

    @Test("A request still failing 71 hours after its record was tracked is sent no more, and is reported as deadlineExceeded rather than delivered")
    func reportedNotDelivered() async throws {
        let tracked = Date(timeIntervalSince1970: 1_795_442_607)
        let hours71: TimeInterval = 255_600
        let clock = TestClock()
        let origin = clock.now
        // The wall clock starts 1.5 seconds before the 71 hours end and follows the test clock, so
        // the attempts at 0 and 1 second are inside them and the one after the 2-second wait isn't.
        let start = tracked.addingTimeInterval(hours71 - 1.5)
        let now: @Sendable () -> Date = {
            let elapsed = origin.duration(to: clock.now).components
            return start.addingTimeInterval(Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18)
        }
        let transport = ScriptedTransport([.status(.serviceUnavailable)])
        let sut = try HTTPDestination.googleAnalytics(measurementID: "G-TEST000000", apiSecret: "testapisecret", region: .global, plan: try TrackingPlan(schemas: [Searched.schema]), transport: transport, backoff: ExponentialBackoff(jitter: .none), clock: clock, now: now)
        let batch = [EventRecord(event: Searched(query: "a"), timestamp: tracked, sourceLocation: nil)]
        let expected = HTTPDropReport<GoogleAnalyticsEncodingError>.deadlineExceeded(deadline: tracked.addingTimeInterval(hours71), recordIDs: batch.map(\.id))
        let expectedRequestCount = 2
        let receiving = Task { await sut.receive(batch) }

        for wait in [Duration.seconds(1), .seconds(2)] {
            while (try? await clock.checkSuspension()) != nil {}
            await clock.advance(by: wait)
        }
        await receiving.value

        var reports = sut.dropReports.makeAsyncIterator()
        let actual = await reports.next()
        #expect(actual == expected)
        #expect(transport.requests.count == expectedRequestCount)
    }

    @Test("A destination whose clock reads NaN sends nothing, and reports each request as deadlineExceeded, as no deadline can be checked against it")
    func nanClock() async throws {
        let tracked = Date(timeIntervalSince1970: 1_795_442_607)
        let hours71: TimeInterval = 255_600
        let transport = ScriptedTransport([.status(.noContent)])
        let sut = try HTTPDestination.googleAnalytics(measurementID: "G-TEST000000", apiSecret: "testapisecret", region: .global, plan: try TrackingPlan(schemas: [Searched.schema]), transport: transport, now: { Date(timeIntervalSince1970: .nan) })
        let batch = [EventRecord(event: Searched(query: "a"), timestamp: tracked, sourceLocation: nil)]
        let expected = HTTPDropReport<GoogleAnalyticsEncodingError>.deadlineExceeded(deadline: tracked.addingTimeInterval(hours71), recordIDs: batch.map(\.id))

        await sut.receive(batch)

        var reports = sut.dropReports.makeAsyncIterator()
        let actual = await reports.next()
        #expect(actual == expected)
        #expect(transport.requests.isEmpty)
    }
}
#endif
