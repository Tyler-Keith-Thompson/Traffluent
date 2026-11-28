import EventMacros
import Foundation
import HTTPDestinations
import MixpanelEncoding
import PropertyJSON
import Testing
import TrackingPlans

@Suite("MixpanelBatchEncoder: splitting batches")
struct MixpanelBatchSplittingTests {
    @Event(name: "searched")
    struct Searched {
        var query: String
    }

    @Test("Mixpanel's limit is 2,000 events and 2,000,000 bytes a request, and 999,999 bytes an event")
    func mixpanelLimit() {
        let expectedCount = 2_000
        let expectedBytes = 2_000_000
        let expectedRecordBytes = 999_999

        let actual = MixpanelBatchEncoder.batchLimit

        #expect(actual.maximumRecordCount == expectedCount)
        #expect(actual.maximumByteCount == expectedBytes)
        #expect(actual.maximumRecordByteCount == expectedRecordBytes)
    }

    @Test("By default, 2,000 events go in one request, and a 2,001st starts another", arguments: [(1, [1]), (2_000, [2_000]), (2_001, [2_000, 1])])
    func defaultCount(recordCount: Int, expected: [Int]) throws {
        let sut = MixpanelBatchEncoder(projectToken: "testprojecttoken", plan: try TrackingPlan(schemas: [Searched.schema]), now: { Date(timeIntervalSince1970: 1_795_442_607) })
        let batch = (0 ..< recordCount).map { index in
            EventRecord(event: Searched(query: "q\(index)"), timestamp: Date(timeIntervalSince1970: 1_795_442_607 + Double(index)), sourceLocation: nil)
        }

        let actual = sut.requests(for: batch).requests.map(\.recordIDs.count)

        #expect(actual == expected)
    }

    @Test("A batch over the limit's count is split into requests in order, each of them the body an unsplit encoder writes for its records")
    func splitByCount() throws {
        let plan = try TrackingPlan(schemas: [Searched.schema])
        let limit = try BatchLimit(maximumRecordCount: 2, maximumByteCount: .max, maximumRecordByteCount: .max)
        let sut = MixpanelBatchEncoder(projectToken: "testprojecttoken", plan: plan, limit: limit, now: { Date(timeIntervalSince1970: 1_795_442_607) })
        let unsplit = MixpanelBatchEncoder(projectToken: "testprojecttoken", plan: plan, now: { Date(timeIntervalSince1970: 1_795_442_607) })
        let batch = (0 ..< 5).map { index in
            EventRecord(event: Searched(query: "q\(index)"), timestamp: Date(timeIntervalSince1970: 1_795_442_607 + Double(index)), sourceLocation: nil)
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

    @Test("A batch over the limit's bytes is split so each request's body fits, and one exactly at the limit isn't")
    func splitByBytes() throws {
        let plan = try TrackingPlan(schemas: [Searched.schema])
        let records = (0 ..< 3).map { index in
            EventRecord(event: Searched(query: "q\(index)"), timestamp: Date(timeIntervalSince1970: 1_795_442_607 + Double(index)), sourceLocation: nil)
        }
        let unsplit = MixpanelBatchEncoder(projectToken: "testprojecttoken", plan: plan, now: { Date(timeIntervalSince1970: 1_795_442_607) })
        let twoRecordBytes = try #require(unsplit.requests(for: Array(records[0 ..< 2])).requests.first).body.body.count
        let exact = MixpanelBatchEncoder(projectToken: "testprojecttoken", plan: plan, limit: try BatchLimit(maximumRecordCount: .max, maximumByteCount: twoRecordBytes, maximumRecordByteCount: .max), now: { Date(timeIntervalSince1970: 1_795_442_607) })
        let short = MixpanelBatchEncoder(projectToken: "testprojecttoken", plan: plan, limit: try BatchLimit(maximumRecordCount: .max, maximumByteCount: twoRecordBytes - 1, maximumRecordByteCount: .max), now: { Date(timeIntervalSince1970: 1_795_442_607) })
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
        // The array's brackets.
        let envelopeBytes = 2
        let small = EventRecord(event: Searched(query: "q"), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let large = EventRecord(event: Searched(query: String(repeating: "x", count: 500)), timestamp: Date(timeIntervalSince1970: 1_795_442_608), sourceLocation: nil)
        let unsplit = MixpanelBatchEncoder(projectToken: "testprojecttoken", plan: plan, now: { Date(timeIntervalSince1970: 1_795_442_607) })
        let largeBytes = try #require(unsplit.requests(for: [large]).requests.first).body.body.count - envelopeBytes
        let atLimit = MixpanelBatchEncoder(projectToken: "testprojecttoken", plan: plan, limit: try BatchLimit(maximumRecordCount: .max, maximumByteCount: .max, maximumRecordByteCount: largeBytes), now: { Date(timeIntervalSince1970: 1_795_442_607) })
        let underLimit = MixpanelBatchEncoder(projectToken: "testprojecttoken", plan: plan, limit: try BatchLimit(maximumRecordCount: .max, maximumByteCount: .max, maximumRecordByteCount: largeBytes - 1), now: { Date(timeIntervalSince1970: 1_795_442_607) })
        let expectedSkipped = [SkippedRecord<MixpanelEncodingError>(recordID: large.id, eventName: "searched", schemaVersion: 1, reason: .oversized(byteCount: largeBytes))]
        let expectedSent = [small.id]

        let actualAtLimit = atLimit.requests(for: [small, large])
        let actualUnderLimit = underLimit.requests(for: [small, large])

        #expect(actualAtLimit.skippedRecords.isEmpty)
        #expect(actualAtLimit.requests.flatMap(\.recordIDs) == [small.id, large.id])
        #expect(actualUnderLimit.skippedRecords == expectedSkipped)
        #expect(actualUnderLimit.requests.flatMap(\.recordIDs) == expectedSent)
    }

    @Test("By default, an event of 999,999 bytes is sent and one of 1,000,000 is left out as oversized, and the rest is sent")
    func oversizedForMixpanel() throws {
        let plan = try TrackingPlan(schemas: [Searched.schema])
        let sut = MixpanelBatchEncoder(projectToken: "testprojecttoken", plan: plan, now: { Date(timeIntervalSince1970: 1_795_442_607) })
        let probe = EventRecord(event: Searched(query: ""), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        // An event's JSON without its query's characters: the probe's body less the array's brackets.
        let overhead = try #require(sut.requests(for: [probe]).requests.first).body.body.count - 2
        let small = EventRecord(event: Searched(query: "q"), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let atLimit = EventRecord(event: Searched(query: String(repeating: "x", count: 999_999 - overhead)), timestamp: Date(timeIntervalSince1970: 1_795_442_608), sourceLocation: nil)
        let overLimit = EventRecord(event: Searched(query: String(repeating: "x", count: 1_000_000 - overhead)), timestamp: Date(timeIntervalSince1970: 1_795_442_609), sourceLocation: nil)
        let expectedSkipped = [SkippedRecord<MixpanelEncodingError>(recordID: overLimit.id, eventName: "searched", schemaVersion: 1, reason: .oversized(byteCount: 1_000_000))]
        let expectedSent = [small.id, atLimit.id]

        let actual = sut.requests(for: [small, atLimit, overLimit])

        #expect(actual.skippedRecords == expectedSkipped)
        #expect(actual.requests.flatMap(\.recordIDs) == expectedSent)
        #expect(actual.requests.allSatisfy { $0.body.body.count <= 2_000_000 })
    }

    @Test("By default, events totalling more than 2,000,000 bytes go in more than one request, each within it")
    func splitByMixpanelBytes() throws {
        let sut = MixpanelBatchEncoder(projectToken: "testprojecttoken", plan: try TrackingPlan(schemas: [Searched.schema]), now: { Date(timeIntervalSince1970: 1_795_442_607) })
        // Three events of about 800,000 bytes: two fit in 2,000,000 bytes, three don't.
        let batch = (0 ..< 3).map { index in
            EventRecord(event: Searched(query: String(repeating: "x", count: 800_000)), timestamp: Date(timeIntervalSince1970: 1_795_442_607 + Double(index)), sourceLocation: nil)
        }
        let expected = [2, 1]

        let actual = sut.requests(for: batch)

        #expect(actual.requests.map(\.recordIDs.count) == expected)
        #expect(actual.requests.allSatisfy { $0.body.body.count <= 2_000_000 })
        #expect(actual.skippedRecords.isEmpty)
    }

    @Test("An empty batch makes no request")
    func emptyBatch() throws {
        let sut = MixpanelBatchEncoder(projectToken: "testprojecttoken", plan: try TrackingPlan(schemas: [Searched.schema]), now: { Date(timeIntervalSince1970: 1_795_442_607) })

        let actual = sut.requests(for: [])

        #expect(actual.requests.isEmpty)
        #expect(actual.skippedRecords.isEmpty)
    }
}
