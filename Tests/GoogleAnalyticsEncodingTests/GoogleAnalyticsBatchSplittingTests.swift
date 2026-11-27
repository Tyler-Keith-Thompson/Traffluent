// The module is compiled for macOS and Linux alone (Sources/GoogleAnalyticsEncoding).
#if os(macOS) || os(Linux)
import EventMacros
import Foundation
import GoogleAnalyticsEncoding
import HTTPDestinations
import Instrumentation
import PropertyJSON
import Sessions
import Testing
import TrackingPlans

@Suite("GoogleAnalyticsBatchEncoder: splitting batches")
struct GoogleAnalyticsBatchSplittingTests {
    @Event(name: "searched")
    struct Searched {
        var query: String
    }

    // https://developers.google.com/analytics/devguides/collection/protocol/ga4/reference: 25
    // events a request, a body "less than 130kB"; the validation server refused one of 128,151
    // bytes on 2026-11-27.
    @Test("The Measurement Protocol's limit is 25 events and 100,000 bytes a request, an event's included")
    func measurementProtocolLimit() {
        let expectedCount = 25
        let expectedBytes = 100_000
        let expectedRecordBytes = 100_000

        let actual = GoogleAnalyticsBatchEncoder.batchLimit

        #expect(actual.maximumRecordCount == expectedCount)
        #expect(actual.maximumByteCount == expectedBytes)
        #expect(actual.maximumRecordByteCount == expectedRecordBytes)
    }

    @Test("By default, a session's 25 events go in one request, and a 26th starts another", arguments: [(1, [1]), (25, [25]), (26, [25, 1]), (51, [25, 25, 1])])
    func defaultCount(recordCount: Int, expected: [Int]) throws {
        let sut = GoogleAnalyticsBatchEncoder(plan: try TrackingPlan(schemas: [Searched.schema]), now: { Date(timeIntervalSince1970: 1_795_442_700) })
        var context = ServiceContext.topLevel
        context[SessionKey.self] = UUID(uuidString: "01A208B7-E840-7A3E-8B4D-5C6E7F801234")!
        let batch = (0 ..< recordCount).map { index in
            EventRecord(event: Searched(query: "q\(index)"), timestamp: Date(timeIntervalSince1970: 1_795_442_607 + Double(index)), sourceLocation: nil, context: context)
        }

        let actual = sut.requests(for: batch).requests.map(\.recordIDs.count)

        #expect(actual == expected)
    }

    @Test("A session's records over the limit's count are split into requests in order, each the request an unsplit encoder makes of its records")
    func splitByCount() throws {
        let plan = try TrackingPlan(schemas: [Searched.schema])
        let limit = try BatchLimit(maximumRecordCount: 2, maximumByteCount: .max, maximumRecordByteCount: .max)
        let sut = GoogleAnalyticsBatchEncoder(plan: plan, limit: limit, now: { Date(timeIntervalSince1970: 1_795_442_700) })
        let unsplit = GoogleAnalyticsBatchEncoder(plan: plan, now: { Date(timeIntervalSince1970: 1_795_442_700) })
        var context = ServiceContext.topLevel
        context[SessionKey.self] = UUID(uuidString: "01A208B7-E840-7A3E-8B4D-5C6E7F801234")!
        let batch = (0 ..< 5).map { index in
            EventRecord(event: Searched(query: "q\(index)"), timestamp: Date(timeIntervalSince1970: 1_795_442_607 + Double(index)), sourceLocation: nil, context: context)
        }
        let expected = [
            try #require(unsplit.requests(for: Array(batch[0 ..< 2])).requests.first),
            try #require(unsplit.requests(for: Array(batch[2 ..< 4])).requests.first),
            try #require(unsplit.requests(for: Array(batch[4 ..< 5])).requests.first),
        ]

        let actual = sut.requests(for: batch)

        #expect(actual.requests == expected)
        #expect(actual.skippedRecords.isEmpty)
    }

    @Test("Each session's records are split to the limit's count apart from the others'")
    func splitPerSession() throws {
        let limit = try BatchLimit(maximumRecordCount: 2, maximumByteCount: .max, maximumRecordByteCount: .max)
        let sut = GoogleAnalyticsBatchEncoder(plan: try TrackingPlan(schemas: [Searched.schema]), limit: limit, now: { Date(timeIntervalSince1970: 1_795_442_700) })
        let sessions = [UUID(uuidString: "00000000-0000-4000-8000-00000000000A")!, UUID(uuidString: "00000000-0000-4000-8000-00000000000B")!]
        // Sessions A, B, A, A, B, A: A's four records make two requests, B's two one.
        let batch = [0, 1, 0, 0, 1, 0].enumerated().map { index, session in
            var context = ServiceContext.topLevel
            context[SessionKey.self] = sessions[session]
            return EventRecord(event: Searched(query: "q\(index)"), timestamp: Date(timeIntervalSince1970: 1_795_442_607 + Double(index)), sourceLocation: nil, context: context)
        }
        let expected = [[batch[0].id, batch[2].id], [batch[3].id, batch[5].id], [batch[1].id, batch[4].id]]

        let actual = sut.requests(for: batch).requests.map(\.recordIDs)

        #expect(actual == expected)
    }

    @Test("A batch over the limit's bytes is split so each request's body fits, and one exactly at the limit isn't")
    func splitByBytes() throws {
        let plan = try TrackingPlan(schemas: [Searched.schema])
        var context = ServiceContext.topLevel
        context[SessionKey.self] = UUID(uuidString: "01A208B7-E840-7A3E-8B4D-5C6E7F801234")!
        let records = (0 ..< 3).map { index in
            EventRecord(event: Searched(query: "q\(index)"), timestamp: Date(timeIntervalSince1970: 1_795_442_607 + Double(index)), sourceLocation: nil, context: context)
        }
        let unsplit = GoogleAnalyticsBatchEncoder(plan: plan, now: { Date(timeIntervalSince1970: 1_795_442_700) })
        let twoRecordBytes = try #require(unsplit.requests(for: Array(records[0 ..< 2])).requests.first).body.body.count
        let exact = GoogleAnalyticsBatchEncoder(plan: plan, limit: try BatchLimit(maximumRecordCount: .max, maximumByteCount: twoRecordBytes, maximumRecordByteCount: .max), now: { Date(timeIntervalSince1970: 1_795_442_700) })
        let short = GoogleAnalyticsBatchEncoder(plan: plan, limit: try BatchLimit(maximumRecordCount: .max, maximumByteCount: twoRecordBytes - 1, maximumRecordByteCount: .max), now: { Date(timeIntervalSince1970: 1_795_442_700) })
        let expectedExact = [2, 1]
        let expectedShort = [1, 1, 1]

        let actualExact = exact.requests(for: records).requests.map(\.recordIDs.count)
        let actualShort = short.requests(for: records).requests.map(\.recordIDs.count)

        #expect(actualExact == expectedExact)
        #expect(actualShort == expectedShort)
    }

    @Test("An event over the limit's bytes for one event is left out as oversized with its size, and the rest is sent; one at the limit is sent")
    func oversizedEvent() throws {
        let plan = try TrackingPlan(schemas: [Searched.schema])
        var context = ServiceContext.topLevel
        context[SessionKey.self] = UUID(uuidString: "01A208B7-E840-7A3E-8B4D-5C6E7F801234")!
        let small = EventRecord(event: Searched(query: "q"), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil, context: context)
        let large = EventRecord(event: Searched(query: String(repeating: "x", count: 100)), timestamp: Date(timeIntervalSince1970: 1_795_442_608), sourceLocation: nil, context: context)
        let unsplit = GoogleAnalyticsBatchEncoder(plan: plan, now: { Date(timeIntervalSince1970: 1_795_442_700) })
        // The envelope: everything in the small record's body but its event.
        let smallEvent = #"{"name":"searched","params":{"query":"q","session_id":1795442600000},"timestamp_micros":1795442607000000}"#
        let envelope = try #require(unsplit.requests(for: [small]).requests.first).body.body.count - smallEvent.utf8.count
        let largeBytes = try #require(unsplit.requests(for: [large]).requests.first).body.body.count - envelope
        let atLimit = GoogleAnalyticsBatchEncoder(plan: plan, limit: try BatchLimit(maximumRecordCount: .max, maximumByteCount: .max, maximumRecordByteCount: largeBytes), now: { Date(timeIntervalSince1970: 1_795_442_700) })
        let underLimit = GoogleAnalyticsBatchEncoder(plan: plan, limit: try BatchLimit(maximumRecordCount: .max, maximumByteCount: .max, maximumRecordByteCount: largeBytes - 1), now: { Date(timeIntervalSince1970: 1_795_442_700) })
        let expectedSkipped = [SkippedRecord<GoogleAnalyticsEncodingError>(recordID: large.id, eventName: "searched", schemaVersion: 1, reason: .oversized(byteCount: largeBytes))]
        let expectedSent = [small.id]

        let actualAtLimit = atLimit.requests(for: [small, large])
        let actualUnderLimit = underLimit.requests(for: [small, large])

        #expect(actualAtLimit.skippedRecords.isEmpty)
        #expect(actualAtLimit.requests.flatMap(\.recordIDs) == [small.id, large.id])
        #expect(actualUnderLimit.skippedRecords == expectedSkipped)
        #expect(actualUnderLimit.requests.flatMap(\.recordIDs) == expectedSent)
    }

    @Test("By default, 25 events of strings JSON escapes to 600 bytes each go in more than one request, each within 100,000 bytes")
    func splitByMeasurementProtocolBytes() throws {
        struct Escaped: Event, Codable {
            static let name = "escaped"
            var values: [String: String]
        }
        let schema = EventSchema(name: "escaped", version: 1, consentCategory: .analytics, properties: [])
        let sut = GoogleAnalyticsBatchEncoder(plan: try TrackingPlan(schemas: [schema]), now: { Date(timeIntervalSince1970: 1_795_442_700) })
        var context = ServiceContext.topLevel
        context[SessionKey.self] = UUID(uuidString: "01A208B7-E840-7A3E-8B4D-5C6E7F801234")!
        // 100 control characters, within the 100 bytes a value takes, which JSON writes as \u0001:
        // 600 bytes a value, 24 values about 14,800 bytes an event, so 25 events need two requests.
        let control = String(repeating: "\u{1}", count: 100)
        let values = Dictionary(uniqueKeysWithValues: (0 ..< 24).map { ("v\($0)", control) })
        let batch = (0 ..< 25).map { index in
            EventRecord(event: Escaped(values: values), timestamp: Date(timeIntervalSince1970: 1_795_442_607 + Double(index)), sourceLocation: nil, context: context)
        }

        let actual = sut.requests(for: batch)

        #expect(actual.requests.count > 1)
        #expect(actual.requests.flatMap(\.recordIDs) == batch.map(\.id))
        #expect(actual.requests.allSatisfy { $0.body.body.count <= 100_000 })
        #expect(actual.skippedRecords.isEmpty)
    }

    @Test("An empty batch makes no request")
    func emptyBatch() throws {
        let sut = GoogleAnalyticsBatchEncoder(plan: try TrackingPlan(schemas: [Searched.schema]), now: { Date(timeIntervalSince1970: 1_795_442_700) })

        let actual = sut.requests(for: [])

        #expect(actual.requests.isEmpty)
        #expect(actual.skippedRecords.isEmpty)
    }
}
#endif
