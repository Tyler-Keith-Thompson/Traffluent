import EventMacros
import Foundation
import HTTPDestinations
import PostHogEncoding
import PropertyJSON
import Testing
import TrackingPlans

@Suite("PostHogBatchEncoder: splitting batches")
struct PostHogBatchSplittingTests {
    @Event(name: "searched")
    struct Searched {
        var query: String
    }

    @Test("PostHog's limit is 10,000,000 bytes a request and 1,000,000 an event, with no limit on the count")
    func postHogLimit() {
        let expectedCount = Int.max
        let expectedBytes = 10_000_000
        let expectedRecordBytes = 1_000_000

        let actual = PostHogBatchEncoder.batchLimit

        #expect(actual.maximumRecordCount == expectedCount)
        #expect(actual.maximumByteCount == expectedBytes)
        #expect(actual.maximumRecordByteCount == expectedRecordBytes)
    }

    @Test("A batch over the limit's count is split into requests in order, each of them the body an unsplit encoder writes for its records")
    func splitByCount() throws {
        let plan = try TrackingPlan(schemas: [Searched.schema])
        let limit = try BatchLimit(maximumRecordCount: 2, maximumByteCount: .max, maximumRecordByteCount: .max)
        let sut = PostHogBatchEncoder(projectToken: "phc_test", plan: plan, limit: limit)
        let unsplit = PostHogBatchEncoder(projectToken: "phc_test", plan: plan)
        let batch = (0 ..< 5).map { index in
            EventRecord(event: Searched(query: "q\(index)"), timestamp: Date(timeIntervalSince1970: Double(index)), sourceLocation: nil)
        }
        let expected = [
            EncodedRequest(body: try #require(unsplit.requests(for: Array(batch[0 ..< 2])).requests.first).body, recordIDs: batch[0 ..< 2].map(\.id)),
            EncodedRequest(body: try #require(unsplit.requests(for: Array(batch[2 ..< 4])).requests.first).body, recordIDs: batch[2 ..< 4].map(\.id)),
            EncodedRequest(body: try #require(unsplit.requests(for: Array(batch[4 ..< 5])).requests.first).body, recordIDs: batch[4 ..< 5].map(\.id)),
        ]

        let actual = sut.requests(for: batch)

        #expect(actual.requests == expected)
        #expect(actual.skippedRecords.isEmpty)
    }

    @Test("A batch over the limit's bytes is split so each request's body fits, and one exactly at the limit isn't")
    func splitByBytes() throws {
        let plan = try TrackingPlan(schemas: [Searched.schema])
        let records = (0 ..< 3).map { index in
            EventRecord(event: Searched(query: "q\(index)"), timestamp: Date(timeIntervalSince1970: Double(index)), sourceLocation: nil)
        }
        let unsplit = PostHogBatchEncoder(projectToken: "phc_test", plan: plan)
        let twoRecordBytes = try #require(unsplit.requests(for: Array(records[0 ..< 2])).requests.first).body.body.count
        let exact = PostHogBatchEncoder(projectToken: "phc_test", plan: plan, limit: try BatchLimit(maximumRecordCount: .max, maximumByteCount: twoRecordBytes, maximumRecordByteCount: .max))
        let short = PostHogBatchEncoder(projectToken: "phc_test", plan: plan, limit: try BatchLimit(maximumRecordCount: .max, maximumByteCount: twoRecordBytes - 1, maximumRecordByteCount: .max))
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
        // {"api_key":"phc_test","batch":[ and ]}
        let envelopeBytes = 33
        let small = EventRecord(event: Searched(query: "q"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)
        let large = EventRecord(event: Searched(query: String(repeating: "x", count: 500)), timestamp: Date(timeIntervalSince1970: 1), sourceLocation: nil)
        let unsplit = PostHogBatchEncoder(projectToken: "phc_test", plan: plan)
        let largeBytes = try #require(unsplit.requests(for: [large]).requests.first).body.body.count - envelopeBytes
        let atLimit = PostHogBatchEncoder(projectToken: "phc_test", plan: plan, limit: try BatchLimit(maximumRecordCount: .max, maximumByteCount: .max, maximumRecordByteCount: largeBytes))
        let underLimit = PostHogBatchEncoder(projectToken: "phc_test", plan: plan, limit: try BatchLimit(maximumRecordCount: .max, maximumByteCount: .max, maximumRecordByteCount: largeBytes - 1))
        let expectedSkipped = [SkippedRecord<PostHogEncodingError>(recordID: large.id, eventName: "searched", schemaVersion: 1, reason: .oversized(byteCount: largeBytes))]
        let expectedSent = [small.id]

        let actualAtLimit = atLimit.requests(for: [small, large])
        let actualUnderLimit = underLimit.requests(for: [small, large])

        #expect(actualAtLimit.skippedRecords.isEmpty)
        #expect(actualAtLimit.requests.flatMap(\.recordIDs) == [small.id, large.id])
        #expect(actualUnderLimit.skippedRecords == expectedSkipped)
        #expect(actualUnderLimit.requests.flatMap(\.recordIDs) == expectedSent)
    }

    @Test("An empty batch makes no request")
    func emptyBatch() throws {
        let sut = PostHogBatchEncoder(projectToken: "phc_test", plan: try TrackingPlan(schemas: [Searched.schema]))

        let actual = sut.requests(for: [])

        #expect(actual.requests.isEmpty)
        #expect(actual.skippedRecords.isEmpty)
    }
}
