import EventMacros
import Foundation
import HeapEncoding
import HTTPDestinations
import PropertyJSON
import Testing
import TrackingPlans

// The limits are HeapBatchEncoder.batchLimit's: 1,000 events a request, Bulk Track's "max of 1000
// events per request" (https://developers.heap.io/reference/bulk-track, read 2026-11-27), and
// 1,000,000 bytes a request and an event, the encoder's own bound, as Heap documents none.
@Suite("HeapBatchEncoder: splitting batches")
struct HeapBatchSplittingTests {
    @Event(name: "searched")
    struct Searched {
        var query: String
    }

    /// An event of the properties its test gives, by name.
    struct PropertiesNamed: Event, Encodable {
        static let name = "properties_named"

        struct Key: CodingKey {
            var stringValue: String
            var intValue: Int? { nil }

            init(stringValue: String) {
                self.stringValue = stringValue
            }

            init?(intValue: Int) {
                nil
            }
        }

        var properties: [String: String]

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: Key.self)
            for (name, value) in properties {
                try container.encode(value, forKey: Key(stringValue: name))
            }
        }
    }

    @Test("The default limit is 1,000 events and 1,000,000 bytes a request, and 1,000,000 bytes an event, records too large for a request left out")
    func defaultLimit() throws {
        let expected = try BatchLimit(maximumRecordCount: 1_000, maximumByteCount: 1_000_000, maximumRecordByteCount: 1_000_000)

        let actual = HeapBatchEncoder.batchLimit

        #expect(actual == expected)
    }

    @Test("By default, 1,000 events go in one request, and 1,001 in two, of 1,000 and 1", arguments: [(1_000, [1_000]), (1_001, [1_000, 1]), (1, [1]), (2_500, [1_000, 1_000, 500])])
    func splitByCount(count: Int, expected: [Int]) throws {
        let sut = try HeapBatchEncoder(appID: "12343283", plan: try TrackingPlan(schemas: [Searched.schema]))
        let batch = (0 ..< count).map { index in
            EventRecord(event: Searched(query: "q\(index)"), timestamp: Date(timeIntervalSince1970: 1_795_442_607 + Double(index)), sourceLocation: nil)
        }

        let actual = sut.requests(for: batch).requests.map(\.recordIDs.count)

        #expect(actual == expected)
    }

    @Test("An empty batch makes no request")
    func emptyBatch() throws {
        let sut = try HeapBatchEncoder(appID: "12343283", plan: try TrackingPlan(schemas: [Searched.schema]))

        let actual = sut.requests(for: [])

        #expect(actual.requests.isEmpty)
        #expect(actual.skippedRecords.isEmpty)
    }

    // An event's values are each under 1,024 characters, so an event as large as a request holds
    // many: `count` properties named p000, p001, ... of 1,000 `x`s each, and `q` of the rest. The
    // envelope, {"app_id":"12343283","events":[ and ]}, is 33 bytes, so an event of 999,967 bytes
    // fills a request alone.
    @Test("By default, an event that fills a request of 1,000,000 bytes alone is sent, and one byte more is left out as oversized")
    func oversizedByDefault() throws {
        let schema = EventSchema(name: "properties_named", version: 1, consentCategory: .analytics, properties: [])
        let sut = try HeapBatchEncoder(appID: "12343283", plan: try TrackingPlan(schemas: [schema]))
        let envelopeBytes = 33
        let full = String(repeating: "x", count: 1_000)
        // Each property adds "pNNN":"<1,000 x>", and a comma: 1,010 bytes.
        let propertyBytes = 1_010
        let probe = EventRecord(event: PropertiesNamed(properties: ["q": ""]), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let probeBytes = try #require(sut.requests(for: [probe]).requests.first).body.body.count - envelopeBytes
        let count = (999_967 - probeBytes) / propertyBytes
        let fill = 999_967 - probeBytes - count * propertyBytes
        var properties: [String: String] = [:]
        for index in 0 ..< count {
            properties[String(format: "p%03d", index)] = full
        }
        var atLimitProperties = properties
        atLimitProperties["q"] = String(repeating: "x", count: fill)
        var overLimitProperties = properties
        overLimitProperties["q"] = String(repeating: "x", count: fill + 1)
        let small = EventRecord(event: PropertiesNamed(properties: ["q": "small"]), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let atLimit = EventRecord(event: PropertiesNamed(properties: atLimitProperties), timestamp: Date(timeIntervalSince1970: 1_795_442_608), sourceLocation: nil)
        let overLimit = EventRecord(event: PropertiesNamed(properties: overLimitProperties), timestamp: Date(timeIntervalSince1970: 1_795_442_609), sourceLocation: nil)
        let expectedSkipped = [SkippedRecord<HeapEncodingError>(recordID: overLimit.id, eventName: "properties_named", schemaVersion: 1, reason: .oversized(byteCount: 999_968))]
        let expectedRequests = [[small.id], [atLimit.id]]
        let expectedAtLimitBytes = 1_000_000

        let actual = sut.requests(for: [small, atLimit, overLimit])

        #expect(actual.skippedRecords == expectedSkipped)
        #expect(actual.requests.map(\.recordIDs) == expectedRequests)
        #expect(actual.requests.last?.body.body.count == expectedAtLimitBytes)
    }

    @Test("A request has no deadline, as Heap documents no window of timestamps it takes")
    func noDeadline() throws {
        let sut = try HeapBatchEncoder(appID: "12343283", plan: try TrackingPlan(schemas: [Searched.schema]))
        let batch = [
            EventRecord(event: Searched(query: "old"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil),
            EventRecord(event: Searched(query: "new"), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil),
        ]

        let actual = sut.requests(for: batch)

        #expect(actual.requests.map(\.deadline) == [nil])
        #expect(actual.skippedRecords.isEmpty)
    }

    @Test("A limit the caller gives replaces the default")
    func customLimit() throws {
        let limit = try BatchLimit(maximumRecordCount: 2, maximumByteCount: HeapBatchEncoder.batchLimit.maximumByteCount, maximumRecordByteCount: HeapBatchEncoder.batchLimit.maximumRecordByteCount)
        let sut = try HeapBatchEncoder(appID: "12343283", plan: try TrackingPlan(schemas: [Searched.schema]), limit: limit)
        let batch = (0 ..< 5).map { index in
            EventRecord(event: Searched(query: "q\(index)"), timestamp: Date(timeIntervalSince1970: 1_795_442_607 + Double(index)), sourceLocation: nil)
        }
        let expected = [2, 2, 1]

        let actual = sut.requests(for: batch).requests.map(\.recordIDs.count)

        #expect(actual == expected)
    }
}
