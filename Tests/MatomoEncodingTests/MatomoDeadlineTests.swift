import Clocks
import DestinationTesting
import EventMacros
import Foundation
import HTTPDestinations
import MatomoEncoding
import PropertyJSON
import Testing
import TrackingPlans

@Suite("MatomoBatchEncoder: request deadlines", .timeLimit(.minutes(1)))
struct MatomoDeadlineTests {
    @Event(name: "searched")
    struct Searched {
        var query: String
    }

    @Test("Each request's deadline is 23 hours after the earliest of its records was tracked, whatever their order")
    func deadlinePerRequest() throws {
        let limit = try BatchLimit(maximumRecordCount: 2, maximumByteCount: .max, maximumRecordByteCount: .max)
        let sut = try MatomoBatchEncoder(siteID: 1, dimensions: [:], category: "Shop", plan: try TrackingPlan(schemas: [Searched.schema]), limit: limit, now: { Date(timeIntervalSince1970: 1_795_442_700) })
        let batch = [610, 600, 620].map { EventRecord(event: Searched(query: "a"), timestamp: Date(timeIntervalSince1970: 1_795_442_000 + TimeInterval($0)), sourceLocation: nil) }
        let hours23: TimeInterval = 82_800
        let expectedIDs = [[batch[0].id, batch[1].id], [batch[2].id]]
        let expectedDeadlines: [Date?] = [1_795_442_600 + hours23, 1_795_442_620 + hours23].map { Date(timeIntervalSince1970: $0) }

        let actual = sut.requests(for: batch).requests

        #expect(actual.map(\.recordIDs) == expectedIDs)
        #expect(actual.map(\.deadline) == expectedDeadlines)
    }

    @Test("A request still failing 23 hours after its record was tracked is sent no more, and is reported as deadlineExceeded rather than answered 200 and lost")
    func reportedNotDelivered() async throws {
        let url = try #require(URL(string: "https://analytics.example.com"))
        let tracked = Date(timeIntervalSince1970: 1_795_442_607)
        let hours23: TimeInterval = 82_800
        let clock = TestClock()
        let origin = clock.now
        // The wall clock starts 1.5 seconds before the 23 hours end and follows the test clock, so
        // the attempts at 0 and 1 second are inside them and the one after the 2-second wait isn't.
        let start = tracked.addingTimeInterval(hours23 - 1.5)
        let now: @Sendable () -> Date = {
            let elapsed = origin.duration(to: clock.now).components
            return start.addingTimeInterval(Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18)
        }
        let transport = ScriptedTransport([.status(.serviceUnavailable)])
        let sut = try HTTPDestination.matomo(url: url, siteID: 1, dimensions: [:], category: "Shop", plan: try TrackingPlan(schemas: [Searched.schema]), transport: transport, clock: clock, now: now)
        let batch = [EventRecord(event: Searched(query: "a"), timestamp: tracked, sourceLocation: nil)]
        let expected = HTTPDropReport<MatomoEncodingError>.deadlineExceeded(deadline: tracked.addingTimeInterval(hours23), recordIDs: batch.map(\.id))
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
}
