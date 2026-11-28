import Clocks
import DestinationTesting
import EventMacros
import Foundation
import HTTPDestinations
import HTTPTypes
import MixpanelEncoding
import PropertyJSON
import Synchronization
import Testing
import TrackingPlans

// Mixpanel's track API takes "events that occurred within the last 5 days" and answers 200 to a
// request whose events it drops (https://developer.mixpanel.com/reference/track-event, read
// 2026-11-27). The encoder keeps an hour off: 119 hours is 428,400 seconds. Its limits are
// /import's, which rejects "time values that are ... more than 1 hour in the future"
// (https://developer.mixpanel.com/reference/import-events, read 2026-11-28): 3,600 seconds.
// Private: its events share their names with other events of this test target, and @Event
// leaves a private type's events out of the link check of names (DefiningEvents, Limits).
@Suite("MixpanelBatchEncoder: the 5-day window and request deadlines", .timeLimit(.minutes(1)))
private struct MixpanelDeadlineTests {
    @Event(name: "searched")
    struct Searched {
        var query: String
    }

    @Test("A record tracked from 119 hours before the batch is encoded to an hour after is sent; one a millisecond outside is left out as timestampOutsideWindow", arguments: [
        (-428_400, false), (-428_400.001, true), (-432_000, true), (-1e9, true), (0, false), (3_600, false), (3_600.001, true), (31_536_000, true),
    ])
    func window(offset: TimeInterval, skipped: Bool) throws {
        let now = Date(timeIntervalSince1970: 1_795_442_607)
        let sut = MixpanelBatchEncoder(projectToken: "testprojecttoken", plan: try TrackingPlan(schemas: [Searched.schema]), now: { now })
        let record = EventRecord(event: Searched(query: "a"), timestamp: now.addingTimeInterval(offset), sourceLocation: nil)
        let expected: [SkippedRecord<MixpanelEncodingError>] = skipped
            ? [SkippedRecord(recordID: record.id, eventName: "searched", schemaVersion: 1, reason: .timestampOutsideWindow)]
            : []

        let actual = sut.requests(for: [record])

        #expect(actual.skippedRecords == expected)
        #expect(actual.requests.flatMap(\.recordIDs) == (skipped ? [] : [record.id]))
    }

    // -315,619,200 seconds is 1960-01-01T00:00:00Z, about 66 years before the clock: outside the
    // window and before 1971 both, and the earlier rule is the one reported, as no clock makes it
    // a time Mixpanel takes.
    @Test("A record of 1960 under a clock of 2026 is left out as unrepresentableTimestamp, not timestampOutsideWindow")
    func before1971UnderAClockOf2026() throws {
        let now = Date(timeIntervalSince1970: 1_795_442_607)
        let sut = MixpanelBatchEncoder(projectToken: "testprojecttoken", plan: try TrackingPlan(schemas: [Searched.schema]), now: { now })
        let record = EventRecord(event: Searched(query: "a"), timestamp: Date(timeIntervalSince1970: -315_619_200), sourceLocation: nil)
        let expected = [SkippedRecord<MixpanelEncodingError>(recordID: record.id, eventName: "searched", schemaVersion: 1, reason: .unrepresentableTimestamp)]

        let actual = sut.requests(for: [record])

        #expect(actual.skippedRecords == expected)
        #expect(actual.requests.isEmpty)
    }

    @Test("Under a clock that reads NaN or infinite, every record is left out as timestampOutsideWindow", arguments: [Double.nan, .infinity, -.infinity])
    func nonFiniteClock(seconds: Double) throws {
        let now = Date(timeIntervalSince1970: seconds)
        let sut = MixpanelBatchEncoder(projectToken: "testprojecttoken", plan: try TrackingPlan(schemas: [Searched.schema]), now: { now })
        let batch = (0 ..< 3).map { EventRecord(event: Searched(query: "q\($0)"), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil) }
        let expected: [MixpanelEncodingError] = Array(repeating: .timestampOutsideWindow, count: 3)

        let actual = sut.requests(for: batch)

        #expect(actual.skippedRecords.map(\.reason) == expected)
        #expect(actual.requests.isEmpty)
    }

    @Test("The clock is read once a batch, when it is encoded", arguments: [1, 3])
    func clockReadOnce(count: Int) throws {
        let reads = Reads()
        let sut = MixpanelBatchEncoder(projectToken: "testprojecttoken", plan: try TrackingPlan(schemas: [Searched.schema]), now: {
            reads.count.withLock { $0 += 1 }
            return Date(timeIntervalSince1970: 1_795_442_607)
        })
        let batch = (0 ..< count).map { _ in EventRecord(event: Searched(query: "a"), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil) }
        let expected = 1

        _ = sut.requests(for: batch)

        let actual = reads.count.withLock { $0 }
        #expect(actual == expected)
    }

    @Test("Each request's deadline is 119 hours after the earliest of its records was tracked, whatever their order")
    func deadlinePerRequest() throws {
        let limit = try BatchLimit(maximumRecordCount: 2, maximumByteCount: .max, maximumRecordByteCount: .max)
        let sut = MixpanelBatchEncoder(projectToken: "testprojecttoken", plan: try TrackingPlan(schemas: [Searched.schema]), limit: limit, now: { Date(timeIntervalSince1970: 1_795_442_700) })
        let batch = [610, 600, 620].map { EventRecord(event: Searched(query: "a"), timestamp: Date(timeIntervalSince1970: 1_795_442_000 + TimeInterval($0)), sourceLocation: nil) }
        let hours119: TimeInterval = 428_400
        let expectedIDs = [[batch[0].id, batch[1].id], [batch[2].id]]
        let expectedDeadlines: [Date?] = [1_795_442_600 + hours119, 1_795_442_620 + hours119].map { Date(timeIntervalSince1970: $0) }

        let actual = sut.requests(for: batch).requests

        #expect(actual.map(\.recordIDs) == expectedIDs)
        #expect(actual.map(\.deadline) == expectedDeadlines)
    }

    @Test("A request still failing 119 hours after its record was tracked is sent no more, and is reported as deadlineExceeded rather than answered 200 and lost")
    func reportedNotDelivered() async throws {
        let tracked = Date(timeIntervalSince1970: 1_795_442_607)
        let hours119: TimeInterval = 428_400
        let clock = TestClock()
        let origin = clock.now
        // The wall clock starts 1.5 seconds before the 119 hours end and follows the test clock,
        // so the attempts at 0 and 1 second are inside them and the one after the 2-second wait
        // isn't.
        let start = tracked.addingTimeInterval(hours119 - 1.5)
        let now: @Sendable () -> Date = {
            let elapsed = origin.duration(to: clock.now).components
            return start.addingTimeInterval(Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18)
        }
        let transport = ScriptedTransport([.status(.serviceUnavailable)])
        let backoff = try ExponentialBackoff(initialDelay: .seconds(1), maximumDelay: .seconds(60), jitter: .none)
        let sut = try HTTPDestination.mixpanel(projectToken: "testprojecttoken", region: .us, plan: try TrackingPlan(schemas: [Searched.schema]), transport: transport, backoff: backoff, clock: clock, now: now)
        let batch = [EventRecord(event: Searched(query: "a"), timestamp: tracked, sourceLocation: nil)]
        let expected = HTTPDropReport<MixpanelEncodingError>.deadlineExceeded(deadline: tracked.addingTimeInterval(hours119), recordIDs: batch.map(\.id))
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

    // 1,000,000,000 seconds after 1970 is 2001-09-09T01:46:40Z: years outside the window of the
    // system's clock, so a factory that left either clock to the system would skip the record or
    // drop its request.
    @Test("The factory's now: is both the encoder's clock and the destination's, so a record of 2001 is sent under a clock of 2001")
    func factoryClockReachesBoth() async throws {
        let tracked = Date(timeIntervalSince1970: 1_000_000_000)
        let transport = ScriptedTransport([.status(.ok), .status(.badRequest)])
        let sut = try HTTPDestination.mixpanel(projectToken: "testprojecttoken", region: .us, plan: try TrackingPlan(schemas: [Searched.schema]), transport: transport, now: { tracked })
        let batch = [EventRecord(event: Searched(query: "a"), timestamp: tracked, sourceLocation: nil)]
        let rejected = [EventRecord(event: Searched(query: "b"), timestamp: tracked, sourceLocation: nil)]
        let expected = HTTPDropReport<MixpanelEncodingError>.rejected(status: .badRequest, recordIDs: rejected.map(\.id))
        let expectedRequestCount = 2

        await sut.receive(batch)
        // Answered with 400, so its report comes first, unless the first batch was skipped or
        // dropped.
        await sut.receive(rejected)

        var reports = sut.dropReports.makeAsyncIterator()
        let actual = await reports.next()
        #expect(actual == expected)
        #expect(transport.requests.count == expectedRequestCount)
    }

    @Test("A stale record beside a fresh one answered with status 0 is reported once, as skipped, and the rejection names the fresh record alone")
    func staleRecordReportedOnce() async throws {
        let now = Date(timeIntervalSince1970: 1_795_442_607)
        let body = Data(#"{"status":0,"error":"<string>"}"#.utf8)
        let transport = ScriptedTransport([.response(.ok, body: body), .status(.badRequest)])
        let sut = try HTTPDestination.mixpanel(projectToken: "testprojecttoken", region: .us, plan: try TrackingPlan(schemas: [Searched.schema]), transport: transport, now: { now })
        let stale = EventRecord(event: Searched(query: "old"), timestamp: now.addingTimeInterval(-432_000), sourceLocation: nil)
        let fresh = EventRecord(event: Searched(query: "new"), timestamp: now, sourceLocation: nil)
        let last = [EventRecord(event: Searched(query: "last"), timestamp: now, sourceLocation: nil)]
        let expected: [HTTPDropReport<MixpanelEncodingError>] = [
            .skipped(SkippedRecord(recordID: stale.id, eventName: "searched", schemaVersion: 1, reason: .timestampOutsideWindow)),
            .rejectedInBody(status: .ok, reason: "<string>", recordIDs: [fresh.id]),
            .rejected(status: .badRequest, recordIDs: last.map(\.id)),
        ]
        let expectedRequestCount = 2

        await sut.receive([stale, fresh])
        // Answered with 400, so its report comes next, and a second report of the first batch
        // would take its place.
        await sut.receive(last)

        var reports = sut.dropReports.makeAsyncIterator()
        var actual: [HTTPDropReport<MixpanelEncodingError>] = []
        for _ in expected.indices {
            if let report = await reports.next() {
                actual.append(report)
            }
        }
        #expect(actual == expected)
        #expect(transport.requests.count == expectedRequestCount)
    }

    /// How many times a clock was read.
    final class Reads: Sendable {
        let count = Mutex(0)
    }
}
