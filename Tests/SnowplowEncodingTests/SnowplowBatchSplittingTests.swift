import EventMacros
import Foundation
import HTTPDestinations
import PropertyJSON
import SnowplowEncoding
import Testing
import TrackingPlans

@Suite("SnowplowBatchEncoder: splitting batches")
struct SnowplowBatchSplittingTests {
    @Event(name: "searched")
    struct Searched {
        var query: String
    }

    @Test("By default, 26 events go in two requests, of 25 and 1")
    func splitByCount() throws {
        let sut = try SnowplowBatchEncoder(vendor: "com.example", appID: "shop", plan: try TrackingPlan(schemas: [Searched.schema]))
        let batch = (0 ..< 26).map { index in
            EventRecord(event: Searched(query: "q\(index)"), timestamp: Date(timeIntervalSince1970: 1_795_442_607 + Double(index)), sourceLocation: nil)
        }
        let expected = [25, 1]

        let actual = sut.requests(for: batch).requests.map(\.recordIDs.count)

        #expect(actual == expected)
    }

    @Test("By default, an event of 150,000 bytes of JSON is sent in a request of its own, and one of 150,001 is left out as oversized")
    func oversizedByDefault() throws {
        let sut = try SnowplowBatchEncoder(vendor: "com.example", appID: "shop", plan: try TrackingPlan(schemas: [Searched.schema]))
        let probe = EventRecord(event: Searched(query: ""), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        // The probe's JSON is its request less the envelope; each `x` of a query adds one byte.
        let envelopeBytes = #"{"data":[],"schema":"iglu:com.snowplowanalytics.snowplow/payload_data/jsonschema/1-0-4"}"#.utf8.count
        let probeBytes = try #require(sut.requests(for: [probe]).requests.first).body.body.count - envelopeBytes
        let small = EventRecord(event: Searched(query: "q"), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let atLimit = EventRecord(event: Searched(query: String(repeating: "x", count: 150_000 - probeBytes)), timestamp: Date(timeIntervalSince1970: 1_795_442_608), sourceLocation: nil)
        let overLimit = EventRecord(event: Searched(query: String(repeating: "x", count: 150_001 - probeBytes)), timestamp: Date(timeIntervalSince1970: 1_795_442_609), sourceLocation: nil)
        let last = EventRecord(event: Searched(query: "r"), timestamp: Date(timeIntervalSince1970: 1_795_442_610), sourceLocation: nil)
        let expectedSkipped = [SkippedRecord<SnowplowEncodingError>(recordID: overLimit.id, eventName: "searched", schemaVersion: 1, reason: .oversized(byteCount: 150_001))]
        let expectedRequests = [[small.id], [atLimit.id], [last.id]]
        let expectedLargeBodyBytes = 150_000 + envelopeBytes

        let actual = sut.requests(for: [small, atLimit, overLimit, last])

        #expect(actual.skippedRecords == expectedSkipped)
        #expect(actual.requests.map(\.recordIDs) == expectedRequests)
        #expect(actual.requests.dropFirst().first?.body.body.count == expectedLargeBodyBytes)
    }

    @Test("By default, two events whose request is exactly 40,000 bytes share it, and with one byte more each is a request of its own")
    func sharedRequestBoundary() throws {
        let sut = try SnowplowBatchEncoder(vendor: "com.example", appID: "shop", plan: try TrackingPlan(schemas: [Searched.schema]))
        let envelopeBytes = #"{"data":[],"schema":"iglu:com.snowplowanalytics.snowplow/payload_data/jsonschema/1-0-4"}"#.utf8.count
        let probe = EventRecord(event: Searched(query: ""), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let probeBytes = try #require(sut.requests(for: [probe]).requests.first).body.body.count - envelopeBytes
        // Two events in a request are the envelope, both events' JSON and a comma between them.
        let queryBytes = 40_000 - envelopeBytes - 2 * probeBytes - 1 - 1
        let first = EventRecord(event: Searched(query: String(repeating: "x", count: queryBytes)), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let longer = EventRecord(event: Searched(query: String(repeating: "x", count: queryBytes + 1)), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let second = EventRecord(event: Searched(query: "q"), timestamp: Date(timeIntervalSince1970: 1_795_442_608), sourceLocation: nil)
        let expectedShared = [[first.id, second.id]]
        let expectedSplit = [[longer.id], [second.id]]
        let expectedBodyBytes = [40_000]

        let actual = sut.requests(for: [first, second])
        let actualSplit = sut.requests(for: [longer, second])

        #expect(actual.requests.map(\.recordIDs) == expectedShared)
        #expect(actual.requests.map(\.body.body.count) == expectedBodyBytes)
        #expect(actualSplit.requests.map(\.recordIDs) == expectedSplit)
    }

    @Test("By default, an event that would take a request past 40,000 bytes, though under 150,000, starts a request of its own")
    func largeEventAlone() throws {
        let sut = try SnowplowBatchEncoder(vendor: "com.example", appID: "shop", plan: try TrackingPlan(schemas: [Searched.schema]))
        let envelopeBytes = #"{"data":[],"schema":"iglu:com.snowplowanalytics.snowplow/payload_data/jsonschema/1-0-4"}"#.utf8.count
        let probe = EventRecord(event: Searched(query: ""), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let probeBytes = try #require(sut.requests(for: [probe]).requests.first).body.body.count - envelopeBytes
        // Alone, its request is exactly 40,000 bytes; beside another, over.
        let atRequestLimit = EventRecord(event: Searched(query: String(repeating: "x", count: 40_000 - envelopeBytes - probeBytes)), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let overRequestLimit = EventRecord(event: Searched(query: String(repeating: "x", count: 40_001 - envelopeBytes - probeBytes)), timestamp: Date(timeIntervalSince1970: 1_795_442_608), sourceLocation: nil)
        let small = EventRecord(event: Searched(query: "q"), timestamp: Date(timeIntervalSince1970: 1_795_442_609), sourceLocation: nil)
        let expectedRequests = [[atRequestLimit.id], [overRequestLimit.id], [small.id]]
        let expectedBodyBytes = [40_000, 40_001]

        let actual = sut.requests(for: [atRequestLimit, overRequestLimit, small])

        #expect(actual.skippedRecords.isEmpty)
        #expect(actual.requests.map(\.recordIDs) == expectedRequests)
        #expect(Array(actual.requests.prefix(2).map(\.body.body.count)) == expectedBodyBytes)
    }

    @Test("By default, events totalling more than 40,000 bytes go in more than one request, each within it")
    func splitByBytes() throws {
        let sut = try SnowplowBatchEncoder(vendor: "com.example", appID: "shop", plan: try TrackingPlan(schemas: [Searched.schema]))
        // Ten events of about 10,000 bytes: three fit in 40,000 bytes, ten don't.
        let batch = (0 ..< 10).map { index in
            EventRecord(event: Searched(query: String(repeating: "x", count: 10_000)), timestamp: Date(timeIntervalSince1970: 1_795_442_607 + Double(index)), sourceLocation: nil)
        }
        let expectedCounts = [3, 3, 3, 1]

        let actual = sut.requests(for: batch)

        #expect(actual.skippedRecords.isEmpty)
        #expect(actual.requests.map(\.recordIDs.count) == expectedCounts)
        #expect(actual.requests.allSatisfy { $0.body.body.count <= 40_000 })
    }
}
