import AptabaseEncoding
import EventMacros
import Foundation
import HTTPDestinations
import PropertyJSON
import Testing
import TrackingPlans

// The limits are AptabaseBatchEncoder.batchLimit's: 25 events a request, the most
// EventsController.Multiple takes ("Too many events ... Maximum is 25.",
// github.com/aptabase/aptabase at 89d36185, read 2026-11-27), and 1,000,000 bytes a request and an
// event, the encoder's own bound, under the server's 30,000,000 and nginx's default 1 MiB.
@Suite("AptabaseBatchEncoder: splitting batches")
struct AptabaseBatchSplittingTests {
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

    @Test("The default limit is 25 events and 1,000,000 bytes a request, and 1,000,000 bytes an event, records too large for a request left out")
    func defaultLimit() throws {
        let expected = try BatchLimit(maximumRecordCount: 25, maximumByteCount: 1_000_000, maximumRecordByteCount: 1_000_000)

        let actual = AptabaseBatchEncoder.batchLimit

        #expect(actual == expected)
    }

    @Test("By default, 25 events go in one request, and 26 in two, of 25 and 1", arguments: [(25, [25]), (26, [25, 1]), (24, [24]), (1, [1]), (60, [25, 25, 10])])
    func splitByCount(count: Int, expected: [Int]) throws {
        let tracked = Date(timeIntervalSince1970: 1_795_442_607)
        let sut = AptabaseBatchEncoder(isDebug: false, plan: try TrackingPlan(schemas: [Searched.schema]), now: { tracked })
        let batch = (0 ..< count).map { index in
            EventRecord(event: Searched(query: "q\(index)"), timestamp: tracked.addingTimeInterval(Double(index)), sourceLocation: nil)
        }

        let actual = sut.requests(for: batch).requests.map(\.recordIDs.count)

        #expect(actual == expected)
    }

    @Test("An empty batch makes no request")
    func emptyBatch() throws {
        let tracked = Date(timeIntervalSince1970: 1_795_442_607)
        let sut = AptabaseBatchEncoder(isDebug: false, plan: try TrackingPlan(schemas: [Searched.schema]), now: { tracked })

        let actual = sut.requests(for: [])

        #expect(actual.requests.isEmpty)
        #expect(actual.skippedRecords.isEmpty)
    }

    // An event's values are each at most 180 characters, so an event as large as a request holds
    // many: `count` properties named p00000, p00001, ... of 180 `x`s each, and `q` of the rest. The
    // envelope, [ and ], is 2 bytes, so an event of 999,998 bytes fills a request alone.
    @Test("By default, an event that fills a request of 1,000,000 bytes alone is sent, and one byte more is left out as oversized")
    func oversizedByDefault() throws {
        let tracked = Date(timeIntervalSince1970: 1_795_442_607)
        let schema = EventSchema(name: "properties_named", version: 1, consentCategory: .analytics, properties: [])
        let sut = AptabaseBatchEncoder(isDebug: false, plan: try TrackingPlan(schemas: [schema]), now: { tracked })
        let envelopeBytes = 2
        let full = String(repeating: "x", count: 180)
        // Each property adds "pNNNNN":"<180 x>", and a comma: 192 bytes.
        let propertyBytes = 192
        let probe = EventRecord(event: PropertiesNamed(properties: ["q": ""]), timestamp: tracked, sourceLocation: nil)
        let probeBytes = try #require(sut.requests(for: [probe]).requests.first).body.body.count - envelopeBytes
        // At most 180 characters a value, so the rest is spread over the last few properties.
        let count = (999_998 - probeBytes) / propertyBytes
        let fill = 999_998 - probeBytes - count * propertyBytes
        var properties: [String: String] = [:]
        for index in 0 ..< count {
            properties[String(format: "p%05d", index)] = full
        }
        var atLimitProperties = properties
        atLimitProperties["q"] = String(repeating: "x", count: fill)
        var overLimitProperties = properties
        overLimitProperties["q"] = String(repeating: "x", count: fill + 1)
        let small = EventRecord(event: PropertiesNamed(properties: ["q": "small"]), timestamp: tracked, sourceLocation: nil)
        let atLimit = EventRecord(event: PropertiesNamed(properties: atLimitProperties), timestamp: tracked, sourceLocation: nil)
        let overLimit = EventRecord(event: PropertiesNamed(properties: overLimitProperties), timestamp: tracked, sourceLocation: nil)
        let expectedSkipped = [SkippedRecord<AptabaseEncodingError>(recordID: overLimit.id, eventName: "properties_named", schemaVersion: 1, reason: .oversized(byteCount: 999_999))]
        let expectedRequests = [[small.id], [atLimit.id]]
        let expectedAtLimitBytes = 1_000_000

        let actual = sut.requests(for: [small, atLimit, overLimit])

        #expect(fill < 180)
        #expect(actual.skippedRecords == expectedSkipped)
        #expect(actual.requests.map(\.recordIDs) == expectedRequests)
        #expect(actual.requests.last?.body.body.count == expectedAtLimitBytes)
    }

    @Test("A limit the caller gives replaces the default")
    func customLimit() throws {
        let tracked = Date(timeIntervalSince1970: 1_795_442_607)
        let limit = try BatchLimit(maximumRecordCount: 2, maximumByteCount: AptabaseBatchEncoder.batchLimit.maximumByteCount, maximumRecordByteCount: AptabaseBatchEncoder.batchLimit.maximumRecordByteCount)
        let sut = AptabaseBatchEncoder(isDebug: false, plan: try TrackingPlan(schemas: [Searched.schema]), limit: limit, now: { tracked })
        let batch = (0 ..< 5).map { index in
            EventRecord(event: Searched(query: "q\(index)"), timestamp: tracked, sourceLocation: nil)
        }
        let expected = [2, 2, 1]

        let actual = sut.requests(for: batch).requests.map(\.recordIDs.count)

        #expect(actual == expected)
    }
}
