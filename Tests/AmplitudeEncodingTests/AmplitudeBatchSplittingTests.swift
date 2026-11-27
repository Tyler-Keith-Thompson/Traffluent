import AmplitudeEncoding
import EventMacros
import Foundation
import HTTPDestinations
import PropertyJSON
import Testing
import TrackingPlans

@Suite("AmplitudeBatchEncoder: splitting batches")
struct AmplitudeBatchSplittingTests {
    @Event(name: "searched")
    struct Searched {
        var query: String
    }

    @Test("Amplitude's limit is 10 events and 1,000,000 bytes a request, an event's included")
    func amplitudeLimit() {
        let expectedCount = 10
        let expectedBytes = 1_000_000
        let expectedRecordBytes = 1_000_000

        let actual = AmplitudeBatchEncoder.batchLimit

        #expect(actual.maximumRecordCount == expectedCount)
        #expect(actual.maximumByteCount == expectedBytes)
        #expect(actual.maximumRecordByteCount == expectedRecordBytes)
    }

    @Test("By default, 10 events go in one request, and an 11th starts another", arguments: [(1, [1]), (10, [10]), (11, [10, 1]), (21, [10, 10, 1])])
    func defaultCount(recordCount: Int, expected: [Int]) throws {
        let sut = AmplitudeBatchEncoder(apiKey: "test-api-key", plan: try TrackingPlan(schemas: [Searched.schema]))
        let batch = (0 ..< recordCount).map { index in
            EventRecord(event: Searched(query: "q\(index)"), timestamp: Date(timeIntervalSince1970: Double(index)), sourceLocation: nil)
        }

        let actual = sut.requests(for: batch).requests.map(\.recordIDs.count)

        #expect(actual == expected)
    }

    @Test("A batch over the limit's count is split into requests in order, each of them the body an unsplit encoder writes for its records")
    func splitByCount() throws {
        let plan = try TrackingPlan(schemas: [Searched.schema])
        let limit = try BatchLimit(maximumRecordCount: 2, maximumByteCount: .max, maximumRecordByteCount: .max)
        let sut = AmplitudeBatchEncoder(apiKey: "test-api-key", plan: plan, limit: limit)
        let unsplit = AmplitudeBatchEncoder(apiKey: "test-api-key", plan: plan)
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
        let unsplit = AmplitudeBatchEncoder(apiKey: "test-api-key", plan: plan)
        let twoRecordBytes = try #require(unsplit.requests(for: Array(records[0 ..< 2])).requests.first).body.body.count
        let exact = AmplitudeBatchEncoder(apiKey: "test-api-key", plan: plan, limit: try BatchLimit(maximumRecordCount: .max, maximumByteCount: twoRecordBytes, maximumRecordByteCount: .max))
        let short = AmplitudeBatchEncoder(apiKey: "test-api-key", plan: plan, limit: try BatchLimit(maximumRecordCount: .max, maximumByteCount: twoRecordBytes - 1, maximumRecordByteCount: .max))
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
        // {"api_key":"test-api-key","events":[ and ]}
        let envelopeBytes = 38
        let small = EventRecord(event: Searched(query: "q"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)
        let large = EventRecord(event: Searched(query: String(repeating: "x", count: 500)), timestamp: Date(timeIntervalSince1970: 1), sourceLocation: nil)
        let unsplit = AmplitudeBatchEncoder(apiKey: "test-api-key", plan: plan)
        let largeBytes = try #require(unsplit.requests(for: [large]).requests.first).body.body.count - envelopeBytes
        let atLimit = AmplitudeBatchEncoder(apiKey: "test-api-key", plan: plan, limit: try BatchLimit(maximumRecordCount: .max, maximumByteCount: .max, maximumRecordByteCount: largeBytes))
        let underLimit = AmplitudeBatchEncoder(apiKey: "test-api-key", plan: plan, limit: try BatchLimit(maximumRecordCount: .max, maximumByteCount: .max, maximumRecordByteCount: largeBytes - 1))
        let expectedSkipped = [SkippedRecord<AmplitudeEncodingError>(recordID: large.id, eventName: "searched", schemaVersion: 1, reason: .oversized(byteCount: largeBytes))]
        let expectedSent = [small.id]

        let actualAtLimit = atLimit.requests(for: [small, large])
        let actualUnderLimit = underLimit.requests(for: [small, large])

        #expect(actualAtLimit.skippedRecords.isEmpty)
        #expect(actualAtLimit.requests.flatMap(\.recordIDs) == [small.id, large.id])
        #expect(actualUnderLimit.skippedRecords == expectedSkipped)
        #expect(actualUnderLimit.requests.flatMap(\.recordIDs) == expectedSent)
    }

    @Test("An event too large for a 1,000,000-byte request is left out by the default limit, and the rest is sent")
    func oversizedForAmplitude() throws {
        let sut = AmplitudeBatchEncoder(apiKey: "test-api-key", plan: try TrackingPlan(schemas: [Searched.schema]))
        let small = EventRecord(event: Searched(query: "q"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)
        let large = EventRecord(event: Searched(query: String(repeating: "x", count: 1_000_000)), timestamp: Date(timeIntervalSince1970: 1), sourceLocation: nil)
        let expectedSkippedIDs = [large.id]
        let expectedSent = [small.id]

        let actual = sut.requests(for: [small, large])

        #expect(actual.skippedRecords.map(\.recordID) == expectedSkippedIDs)
        #expect(actual.requests.flatMap(\.recordIDs) == expectedSent)
        #expect(actual.requests.allSatisfy { $0.body.body.count <= 1_000_000 })
    }

    @Test("An empty batch makes no request")
    func emptyBatch() throws {
        let sut = AmplitudeBatchEncoder(apiKey: "test-api-key", plan: try TrackingPlan(schemas: [Searched.schema]))

        let actual = sut.requests(for: [])

        #expect(actual.requests.isEmpty)
        #expect(actual.skippedRecords.isEmpty)
    }
}
