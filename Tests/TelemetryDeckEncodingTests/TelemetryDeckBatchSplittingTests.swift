import EventMacros
import Foundation
import HTTPDestinations
import PropertyJSON
import TelemetryDeckEncoding
import Testing
import TrackingPlans

// The limits are TelemetryDeckBatchEncoder.batchLimit's: 100 events a request, as TelemetryDeck's
// SwiftSDK sends them, 1,000,000 bytes a request, and 333,333 bytes an event, a third of Ingest API
// v3's 1,000,000-byte limit on an event (https://telemetrydeck.com/docs/ingest/v3/, read
// 2026-11-27), as the server re-encodes each event and escaping may triple it.
@Suite("TelemetryDeckBatchEncoder: splitting batches")
struct TelemetryDeckBatchSplittingTests {
    @Event(name: "searched")
    struct Searched {
        var query: String
    }

    @Test("By default, 100 events go in one request, and 101 in two, of 100 and 1", arguments: [(100, [100]), (101, [100, 1]), (1, [1]), (250, [100, 100, 50])])
    func splitByCount(count: Int, expected: [Int]) throws {
        let sut = try TelemetryDeckBatchEncoder(appID: "B97579B6-FFB8-4AC5-AAA7-DA5796CC5DCE", testMode: false, plan: try TrackingPlan(schemas: [Searched.schema]))
        let batch = (0 ..< count).map { index in
            EventRecord(event: Searched(query: "q\(index)"), timestamp: Date(timeIntervalSince1970: 1_795_442_607 + Double(index)), sourceLocation: nil)
        }

        let actual = sut.requests(for: batch).requests.map(\.recordIDs.count)

        #expect(actual == expected)
    }

    @Test("An empty batch makes no request")
    func emptyBatch() throws {
        let sut = try TelemetryDeckBatchEncoder(appID: "B97579B6-FFB8-4AC5-AAA7-DA5796CC5DCE", testMode: false, plan: try TrackingPlan(schemas: [Searched.schema]))

        let actual = sut.requests(for: [])

        #expect(actual.requests.isEmpty)
        #expect(actual.skippedRecords.isEmpty)
    }

    @Test("By default, an event of 333,333 bytes of JSON is sent, and one of 333,334 is left out as oversized")
    func oversizedByDefault() throws {
        let sut = try TelemetryDeckBatchEncoder(appID: "B97579B6-FFB8-4AC5-AAA7-DA5796CC5DCE", testMode: false, plan: try TrackingPlan(schemas: [Searched.schema]))
        let probe = EventRecord(event: Searched(query: ""), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        // The probe's JSON is its request less the array's brackets; each `x` of a query adds one byte.
        let envelopeBytes = 2
        let probeBytes = try #require(sut.requests(for: [probe]).requests.first).body.body.count - envelopeBytes
        let small = EventRecord(event: Searched(query: "q"), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let atLimit = EventRecord(event: Searched(query: String(repeating: "x", count: 333_333 - probeBytes)), timestamp: Date(timeIntervalSince1970: 1_795_442_608), sourceLocation: nil)
        let overLimit = EventRecord(event: Searched(query: String(repeating: "x", count: 333_334 - probeBytes)), timestamp: Date(timeIntervalSince1970: 1_795_442_609), sourceLocation: nil)
        let last = EventRecord(event: Searched(query: "r"), timestamp: Date(timeIntervalSince1970: 1_795_442_610), sourceLocation: nil)
        let expectedSkipped = [SkippedRecord<TelemetryDeckEncodingError>(recordID: overLimit.id, eventName: "searched", schemaVersion: 1, reason: .oversized(byteCount: 333_334))]
        let expectedRequests = [[small.id, atLimit.id, last.id]]

        let actual = sut.requests(for: [small, atLimit, overLimit, last])

        #expect(actual.skippedRecords == expectedSkipped)
        #expect(actual.requests.map(\.recordIDs) == expectedRequests)
    }

    @Test("By default, events whose request is exactly 1,000,000 bytes share it, and with one byte more the last starts a request of its own")
    func sharedRequestBoundary() throws {
        let sut = try TelemetryDeckBatchEncoder(appID: "B97579B6-FFB8-4AC5-AAA7-DA5796CC5DCE", testMode: false, plan: try TrackingPlan(schemas: [Searched.schema]))
        let envelopeBytes = 2
        let probe = EventRecord(event: Searched(query: ""), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let probeBytes = try #require(sut.requests(for: [probe]).requests.first).body.body.count - envelopeBytes
        // Two full-sized events and a third that fills the request: the brackets, three events'
        // JSON and two commas.
        let full = (0 ..< 2).map { index in
            EventRecord(event: Searched(query: String(repeating: "x", count: 333_333 - probeBytes)), timestamp: Date(timeIntervalSince1970: 1_795_442_607 + Double(index)), sourceLocation: nil)
        }
        let fillingBytes = 1_000_000 - envelopeBytes - 2 * 333_333 - 2
        let filling = EventRecord(event: Searched(query: String(repeating: "x", count: fillingBytes - probeBytes)), timestamp: Date(timeIntervalSince1970: 1_795_442_610), sourceLocation: nil)
        let overfilling = EventRecord(event: Searched(query: String(repeating: "x", count: fillingBytes + 1 - probeBytes)), timestamp: Date(timeIntervalSince1970: 1_795_442_610), sourceLocation: nil)
        let expectedShared = [full.map(\.id) + [filling.id]]
        let expectedSplit = [full.map(\.id), [overfilling.id]]
        let expectedBodyBytes = [1_000_000]

        let actual = sut.requests(for: full + [filling])
        let actualSplit = sut.requests(for: full + [overfilling])

        #expect(actual.requests.map(\.recordIDs) == expectedShared)
        #expect(actual.requests.map(\.body.body.count) == expectedBodyBytes)
        #expect(actualSplit.requests.map(\.recordIDs) == expectedSplit)
    }

    @Test("A limit the caller gives replaces the default")
    func customLimit() throws {
        let limit = try BatchLimit(maximumRecordCount: 2, maximumByteCount: TelemetryDeckBatchEncoder.batchLimit.maximumByteCount, maximumRecordByteCount: TelemetryDeckBatchEncoder.batchLimit.maximumRecordByteCount)
        let sut = try TelemetryDeckBatchEncoder(appID: "B97579B6-FFB8-4AC5-AAA7-DA5796CC5DCE", testMode: false, plan: try TrackingPlan(schemas: [Searched.schema]), limit: limit)
        let batch = (0 ..< 5).map { index in
            EventRecord(event: Searched(query: "q\(index)"), timestamp: Date(timeIntervalSince1970: 1_795_442_607 + Double(index)), sourceLocation: nil)
        }
        let expected = [2, 2, 1]

        let actual = sut.requests(for: batch).requests.map(\.recordIDs.count)

        #expect(actual == expected)
    }
}
