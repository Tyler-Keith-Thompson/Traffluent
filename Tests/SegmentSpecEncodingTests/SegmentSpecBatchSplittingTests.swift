import EventMacros
import Foundation
import HTTPDestinations
import PropertyJSON
import SegmentSpecEncoding
import Testing
import TrackingPlans

@Suite("SegmentSpecBatchEncoder: splitting batches")
struct SegmentSpecBatchSplittingTests {
    @Event(name: "searched")
    struct Searched {
        var query: String
    }

    @Event(name: "t")
    struct Tapped {}

    @Test("The spec's limit is 2,500 calls and 500,000 bytes a request, and 31,999 bytes a call")
    func specLimit() {
        let expectedCount = 2_500
        let expectedBytes = 500_000
        let expectedRecordBytes = 31_999

        let actual = SegmentSpecBatchEncoder.batchLimit

        #expect(actual.maximumRecordCount == expectedCount)
        #expect(actual.maximumByteCount == expectedBytes)
        #expect(actual.maximumRecordByteCount == expectedRecordBytes)
    }

    // Every call is over 200 bytes, 500,000 bytes' share of 2,500 calls, so by default the bytes
    // split a batch before the count does; the count is checked with the byte cap lifted.
    @Test("With the spec's count, 2,500 calls go in one request, and a 2,501st starts another", arguments: [(1, [1]), (2_500, [2_500]), (2_501, [2_500, 1])])
    func specCount(recordCount: Int, expected: [Int]) throws {
        let limit = try BatchLimit(maximumRecordCount: SegmentSpecBatchEncoder.batchLimit.maximumRecordCount, maximumByteCount: .max, maximumRecordByteCount: .max)
        let sut = SegmentSpecBatchEncoder(plan: try TrackingPlan(schemas: [Tapped.schema]), limit: limit)
        let batch = (0 ..< recordCount).map { index in
            EventRecord(event: Tapped(), timestamp: Date(timeIntervalSince1970: 1_795_442_607 + Double(index)), sourceLocation: nil)
        }

        let actual = sut.requests(for: batch)

        #expect(actual.requests.map(\.recordIDs.count) == expected)
    }

    @Test("By default, the shortest calls there are fill a request to 500,000 bytes, under 2,500 of them, and the rest start another")
    func shortestCallsSplitByBytes() throws {
        let sut = SegmentSpecBatchEncoder(plan: try TrackingPlan(schemas: [Tapped.schema]))
        // A one-letter event with no properties and no context.
        let batch = (0 ..< 2_500).map { index in
            EventRecord(event: Tapped(), timestamp: Date(timeIntervalSince1970: 1_795_442_607 + Double(index)), sourceLocation: nil)
        }

        let actual = sut.requests(for: batch)

        #expect(actual.requests.count == 2)
        #expect(actual.requests.flatMap(\.recordIDs) == batch.map(\.id))
        #expect(actual.requests.allSatisfy { $0.body.body.count <= 500_000 })
        #expect(actual.requests.allSatisfy { $0.recordIDs.count < 2_500 })
    }

    @Test("A batch over the limit's count is split into requests in order, each of them the body an unsplit encoder writes for its records")
    func splitByCount() throws {
        let plan = try TrackingPlan(schemas: [Searched.schema])
        let limit = try BatchLimit(maximumRecordCount: 2, maximumByteCount: .max, maximumRecordByteCount: .max)
        let sut = SegmentSpecBatchEncoder(plan: plan, limit: limit)
        let unsplit = SegmentSpecBatchEncoder(plan: plan)
        let batch = (0 ..< 5).map { index in
            EventRecord(event: Searched(query: "q\(index)"), timestamp: Date(timeIntervalSince1970: 1_795_442_607 + Double(index)), sourceLocation: nil)
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
            EventRecord(event: Searched(query: "q\(index)"), timestamp: Date(timeIntervalSince1970: 1_795_442_607 + Double(index)), sourceLocation: nil)
        }
        let unsplit = SegmentSpecBatchEncoder(plan: plan)
        let twoRecordBytes = try #require(unsplit.requests(for: Array(records[0 ..< 2])).requests.first).body.body.count
        let exact = SegmentSpecBatchEncoder(plan: plan, limit: try BatchLimit(maximumRecordCount: .max, maximumByteCount: twoRecordBytes, maximumRecordByteCount: .max))
        let short = SegmentSpecBatchEncoder(plan: plan, limit: try BatchLimit(maximumRecordCount: .max, maximumByteCount: twoRecordBytes - 1, maximumRecordByteCount: .max))
        let expectedExact = [2, 1]
        let expectedShort = [1, 1, 1]

        let actualExact = exact.requests(for: records).requests.map(\.recordIDs.count)
        let actualShort = short.requests(for: records).requests.map(\.recordIDs.count)

        #expect(actualExact == expectedExact)
        #expect(actualShort == expectedShort)
    }

    @Test("By default, a call of 31,999 bytes is sent and one of 32,000 is left out as oversized, and the rest is sent")
    func oversizedForTheSpec() throws {
        let plan = try TrackingPlan(schemas: [Searched.schema])
        let sut = SegmentSpecBatchEncoder(plan: plan)
        let probe = EventRecord(event: Searched(query: ""), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        // A call's JSON without its query's characters: the probe's body less the envelope,
        // `{"batch":[` and `]}`.
        let overhead = try #require(sut.requests(for: [probe]).requests.first).body.body.count - 12
        let small = EventRecord(event: Searched(query: "q"), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let atLimit = EventRecord(event: Searched(query: String(repeating: "x", count: 31_999 - overhead)), timestamp: Date(timeIntervalSince1970: 1_795_442_608), sourceLocation: nil)
        let overLimit = EventRecord(event: Searched(query: String(repeating: "x", count: 32_000 - overhead)), timestamp: Date(timeIntervalSince1970: 1_795_442_609), sourceLocation: nil)
        let expectedSkipped = [SkippedRecord<SegmentSpecEncodingError>(recordID: overLimit.id, eventName: "searched", schemaVersion: 1, reason: .oversized(byteCount: 32_000))]
        let expectedSent = [small.id, atLimit.id]

        let actual = sut.requests(for: [small, atLimit, overLimit])

        #expect(actual.skippedRecords == expectedSkipped)
        #expect(actual.requests.flatMap(\.recordIDs) == expectedSent)
    }

    @Test("By default, calls totalling more than 500,000 bytes go in more than one request, each within it")
    func splitBySpecBytes() throws {
        let sut = SegmentSpecBatchEncoder(plan: try TrackingPlan(schemas: [Searched.schema]))
        // Twenty calls of about 30,000 bytes: sixteen fit in 500,000 bytes, twenty don't.
        let batch = (0 ..< 20).map { index in
            EventRecord(event: Searched(query: String(repeating: "x", count: 30_000)), timestamp: Date(timeIntervalSince1970: 1_795_442_607 + Double(index)), sourceLocation: nil)
        }
        let expected = [16, 4]

        let actual = sut.requests(for: batch)

        #expect(actual.requests.map(\.recordIDs.count) == expected)
        #expect(actual.requests.allSatisfy { $0.body.body.count <= 500_000 })
        #expect(actual.skippedRecords.isEmpty)
    }

    @Test("An empty batch makes no request")
    func emptyBatch() throws {
        let sut = SegmentSpecBatchEncoder(plan: try TrackingPlan(schemas: [Searched.schema]))

        let actual = sut.requests(for: [])

        #expect(actual.requests.isEmpty)
        #expect(actual.skippedRecords.isEmpty)
    }
}
