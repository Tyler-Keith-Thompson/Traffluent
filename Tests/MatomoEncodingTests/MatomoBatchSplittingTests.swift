import EventMacros
import Foundation
import HTTPDestinations
import MatomoEncoding
import PropertyJSON
import Testing
import TrackingPlans

// The limits are MatomoBatchEncoder.batchLimit's: 20 tracking requests a bulk request, as
// Matomo's iOS SDK 7.9.0 sends them (MatomoTracker.swift, numberOfEventsDispatchedAtOnce), and
// 1,000,000 bytes a body, under nginx's default client_max_body_size of 1 MiB. Matomo documents no
// limit of its own (https://developer.matomo.org/api-reference/tracking-api, "Bulk Tracking", read
// 2026-11-27).
// Private: its events share their names with other events of this test target, and @Event
// leaves a private type's events out of the link check of names (DefiningEvents, Limits).
@Suite("MatomoBatchEncoder: splitting batches")
private struct MatomoBatchSplittingTests {
    @Event(name: "searched")
    struct Searched {
        var query: String
    }

    /// An event of as many string properties as its test gives, `p0`, `p1` and on, which only a
    /// hand-written `Encodable` conformance can write.
    struct Wide: Event, Encodable {
        static let name = "wide"
        static let propertyCount = 340
        static let schema = EventSchema(name: name, version: 1, consentCategory: .analytics, properties: (0 ..< propertyCount).map {
            EventSchema.Property(name: "p\($0)", typeName: "String", isOptional: false)
        })

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

        var values: [String]

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: Key.self)
            for (index, value) in values.enumerated() {
                try container.encode(value, forKey: Key(stringValue: "p\(index)"))
            }
        }
    }

    @Test("By default, 20 records go in one request, and 21 in two, of 20 and 1", arguments: [(20, [20]), (21, [20, 1]), (1, [1]), (19, [19]), (45, [20, 20, 5])])
    func splitByCount(count: Int, expected: [Int]) throws {
        let sut = try MatomoBatchEncoder(siteID: 1, dimensions: ["query": 1], category: "Shop", plan: try TrackingPlan(schemas: [Searched.schema]), now: { Date(timeIntervalSince1970: 1_795_442_607) })
        let batch = (0 ..< count).map { index in
            EventRecord(event: Searched(query: "q\(index)"), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        }

        let actual = sut.requests(for: batch).requests.map(\.recordIDs.count)

        #expect(actual == expected)
    }

    @Test("An empty batch makes no request")
    func emptyBatch() throws {
        let sut = try MatomoBatchEncoder(siteID: 1, dimensions: [:], category: "Shop", plan: try TrackingPlan(schemas: [Searched.schema]), now: { Date(timeIntervalSince1970: 1_795_442_607) })

        let actual = sut.requests(for: [])

        #expect(actual.requests.isEmpty)
        #expect(actual.skippedRecords.isEmpty)
    }

    @Test("By default, a record whose request fills a body of 1,000,000 bytes alone is sent, and one a byte larger is left out as oversized")
    func oversizedByDefault() throws {
        let dimensions = MatomoDimensions(Dictionary(uniqueKeysWithValues: (0 ..< Wide.propertyCount).map { ("p\($0)", $0 + 1) }))
        let sut = try MatomoBatchEncoder(siteID: 1, dimensions: dimensions, category: "Shop", plan: try TrackingPlan(schemas: [Wide.schema]), now: { Date(timeIntervalSince1970: 1_795_442_607) })
        // {"requests":[ and ]}.
        let envelopeBytes = 15
        let empty = Array(repeating: "", count: Wide.propertyCount)
        let probe = EventRecord(event: Wide(values: empty), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let probeBytes = try #require(sut.requests(for: [probe]).requests.first).body.body.count - envelopeBytes
        // Each 😀 is 12 bytes percent-encoded and one character as Matomo stores it, so 250 of
        // them, the most a dimension keeps, are 3,000 bytes; an `a` is one byte.
        let target = 1_000_000 - envelopeBytes - probeBytes
        let full = target / 3000
        var values = empty
        for index in 0 ..< full {
            values[index] = String(repeating: "😀", count: 250)
        }
        values[full] = String(repeating: "😀", count: target % 3000 / 12)
        values[full + 1] = String(repeating: "a", count: target % 3000 % 12)
        let atLimit = EventRecord(event: Wide(values: values), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        values[full + 1] += "a"
        let overLimit = EventRecord(event: Wide(values: values), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let expectedBodyBytes = [1_000_000]
        let expectedSkipped = [SkippedRecord<MatomoEncodingError>(recordID: overLimit.id, eventName: "wide", schemaVersion: 1, reason: .oversized(byteCount: 999_986))]

        let actual = sut.requests(for: [atLimit, overLimit])

        #expect(actual.requests.map(\.body.body.count) == expectedBodyBytes)
        #expect(actual.requests.map(\.recordIDs) == [[atLimit.id]])
        #expect(actual.skippedRecords == expectedSkipped)
    }

    @Test("By default, records whose requests fill a body of exactly 1,000,000 bytes share it, and with one byte more the last starts a body of its own")
    func sharedRequestBoundary() throws {
        let dimensions = MatomoDimensions(Dictionary(uniqueKeysWithValues: (0 ..< Wide.propertyCount).map { ("p\($0)", $0 + 1) }))
        let sut = try MatomoBatchEncoder(siteID: 1, dimensions: dimensions, category: "Shop", plan: try TrackingPlan(schemas: [Wide.schema]), now: { Date(timeIntervalSince1970: 1_795_442_607) })
        let envelopeBytes = 15
        let empty = Array(repeating: "", count: Wide.propertyCount)
        let probe = EventRecord(event: Wide(values: empty), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let probeBytes = try #require(sut.requests(for: [probe]).requests.first).body.body.count - envelopeBytes
        // Two records of 400,000 bytes, and a third that fills the body: the envelope, three
        // records and two commas.
        func record(bytes: Int) -> EventRecord {
            let target = bytes - probeBytes
            var values = empty
            for index in 0 ..< target / 3000 {
                values[index] = String(repeating: "😀", count: 250)
            }
            values[target / 3000] = String(repeating: "😀", count: target % 3000 / 12)
            values[target / 3000 + 1] = String(repeating: "a", count: target % 3000 % 12)
            return EventRecord(event: Wide(values: values), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        }
        let large = [record(bytes: 400_000), record(bytes: 400_000)]
        let fillingBytes = 1_000_000 - envelopeBytes - 2 * 400_000 - 2
        let filling = record(bytes: fillingBytes)
        let overfilling = record(bytes: fillingBytes + 1)
        let expectedShared = [large.map(\.id) + [filling.id]]
        let expectedSplit = [large.map(\.id), [overfilling.id]]
        let expectedBodyBytes = [1_000_000]

        let actual = sut.requests(for: large + [filling])
        let actualSplit = sut.requests(for: large + [overfilling])

        #expect(actual.requests.map(\.recordIDs) == expectedShared)
        #expect(actual.requests.map(\.body.body.count) == expectedBodyBytes)
        #expect(actualSplit.requests.map(\.recordIDs) == expectedSplit)
    }

    @Test("A limit the caller gives replaces the default")
    func customLimit() throws {
        let limit = try BatchLimit(maximumRecordCount: 2, maximumByteCount: MatomoBatchEncoder.batchLimit.maximumByteCount, maximumRecordByteCount: MatomoBatchEncoder.batchLimit.maximumRecordByteCount)
        let sut = try MatomoBatchEncoder(siteID: 1, dimensions: [:], category: "Shop", plan: try TrackingPlan(schemas: [Searched.schema]), limit: limit, now: { Date(timeIntervalSince1970: 1_795_442_607) })
        let batch = (0 ..< 5).map { _ in
            EventRecord(event: Searched(query: "q"), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        }
        let expected = [2, 2, 1]

        let actual = sut.requests(for: batch).requests.map(\.recordIDs.count)

        #expect(actual == expected)
    }

    @Test("A request's body is one JSON object of a requests array, with no token_auth or other member")
    func envelope() throws {
        let sut = try MatomoBatchEncoder(siteID: 1, dimensions: [:], category: "Shop", plan: try TrackingPlan(schemas: [Searched.schema]), now: { Date(timeIntervalSince1970: 1_795_442_607) })
        let record = EventRecord(id: UUID(uuidString: "00000000-0000-4000-8000-000000000002")!, event: Searched(query: "q"), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let expectedContentType = "application/json"
        let expectedBody = #"{"requests":["?idsite=1&rec=1&apiv=1&_id=8000000000000002&cdt=1795442607&ca=1&e_c=Shop&e_a=searched"]}"#

        let actual = try #require(sut.requests(for: [record]).requests.first).body

        #expect(actual.contentType == expectedContentType)
        #expect(String(decoding: actual.body, as: UTF8.self) == expectedBody)
    }
}
