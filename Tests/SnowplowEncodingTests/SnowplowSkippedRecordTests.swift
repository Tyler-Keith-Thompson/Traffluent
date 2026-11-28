import EventMacros
import Foundation
import HTTPDestinations
import Instrumentation
import Persistence
import PropertyJSON
import Sessions
import SnowplowEncoding
import Testing
import TrackingPlans

// Private: its events share their names with other events of this test target, and @Event
// leaves a private type's events out of the link check of names (DefiningEvents, Limits).
@Suite("SnowplowBatchEncoder: skipped records")
private struct SnowplowSkippedRecordTests {
    @Event(name: "checkout_started", version: 2)
    struct CheckoutStarted {
        var cartSize: Int
    }

    @Event(name: "measured")
    struct Measured {
        var value: Double
    }

    struct HandWritten: Event {
        var plan: String
    }

    /// An event whose name Iglu doesn't take: it holds a space.
    struct OrderCompleted: Event, Codable {
        static let name = "Order Completed"

        init() {}
    }

    /// An event of version 0, which no SchemaVer has.
    struct Unversioned: Event, Codable {
        static let name = "unversioned"
        static let schemaVersion = 0

        init() {}
    }

    /// Encodes as a bare integer rather than a map of its properties.
    struct NotAMap: Event, Encodable {
        static let name = "not_a_map"

        init() {}

        func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(1)
        }
    }

    @Test("A record whose event the plan doesn't describe is left out as unknownEvent, and the records around it are sent")
    func unknownEvent() throws {
        let sut = try SnowplowBatchEncoder(vendor: "com.example", appID: "shop", plan: try TrackingPlan(schemas: [CheckoutStarted.schema]))
        var context = ServiceContext.topLevel
        context[SessionKey.self] = UUID()
        let skipped = EventRecord(event: Measured(value: 1), timestamp: Date(timeIntervalSince1970: 1_795_442_608), sourceLocation: nil, context: context)
        let batch = [
            EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil, context: context),
            skipped,
            EventRecord(event: CheckoutStarted(cartSize: 3), timestamp: Date(timeIntervalSince1970: 1_795_442_609), sourceLocation: nil, context: context),
        ]
        let expectedBody = try #require(sut.requests(for: [batch[0], batch[2]]).requests.first).body
        let expectedSkipped = [SkippedRecord<SnowplowEncodingError>(recordID: skipped.id, eventName: "measured", schemaVersion: 1, reason: .unknownEvent(name: "measured", version: 1))]

        let actual = sut.requests(for: batch)

        #expect(actual.requests.map(\.body) == [expectedBody])
        #expect(actual.skippedRecords == expectedSkipped)
    }

    @Test("A record whose version the plan doesn't describe is left out as unknownEvent with its version, though the plan has its name")
    func unknownVersion() throws {
        let earlier = EventSchema(name: "checkout_started", version: 1, consentCategory: .analytics, properties: [])
        let sut = try SnowplowBatchEncoder(vendor: "com.example", appID: "shop", plan: try TrackingPlan(schemas: [earlier]))
        let record = EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let expected = [SkippedRecord<SnowplowEncodingError>(recordID: record.id, eventName: "checkout_started", schemaVersion: 2, reason: .unknownEvent(name: "checkout_started", version: 2))]

        let actual = sut.requests(for: [record]).skippedRecords

        #expect(actual == expected)
    }

    @Test("A record whose event name Iglu doesn't take is left out as invalidSchemaKey")
    func invalidName() throws {
        let schema = EventSchema(name: "Order Completed", version: 1, consentCategory: .analytics, properties: [])
        let sut = try SnowplowBatchEncoder(vendor: "com.example", appID: "shop", plan: try TrackingPlan(schemas: [schema]))
        let record = EventRecord(event: OrderCompleted(), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let expected = [SkippedRecord<SnowplowEncodingError>(recordID: record.id, eventName: "Order Completed", schemaVersion: 1, reason: .invalidSchemaKey(name: "Order Completed", version: 1))]

        let actual = sut.requests(for: [record])

        #expect(actual.requests.isEmpty)
        #expect(actual.skippedRecords == expected)
    }

    @Test("A record of version 0, which no SchemaVer has, is left out as invalidSchemaKey")
    func versionZero() throws {
        let schema = EventSchema(name: "unversioned", version: 0, consentCategory: .analytics, properties: [])
        let sut = try SnowplowBatchEncoder(vendor: "com.example", appID: "shop", plan: try TrackingPlan(schemas: [schema]))
        let record = EventRecord(event: Unversioned(), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let expected: [SnowplowEncodingError] = [.invalidSchemaKey(name: "unversioned", version: 0)]

        let actual = sut.requests(for: [record]).skippedRecords.map(\.reason)

        #expect(actual == expected)
    }

    @Test("A record whose name Iglu doesn't take is left out as invalidSchemaKey, though it can't be read either")
    func invalidNameBeforeReading() throws {
        let schema = EventSchema(name: "Order Completed", version: 1, consentCategory: .analytics, properties: [EventSchema.Property(name: "plan", typeName: "String", isOptional: false)])
        let sut = try SnowplowBatchEncoder(vendor: "com.example", appID: "shop", plan: try TrackingPlan(schemas: [schema]))
        let record = EventRecord(event: NamedHandWritten(), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let expected: [SnowplowEncodingError] = [.invalidSchemaKey(name: "Order Completed", version: 1)]

        let actual = sut.requests(for: [record]).skippedRecords.map(\.reason)

        #expect(actual == expected)
    }

    /// An event named as Iglu doesn't take that isn't `Encodable` either.
    struct NamedHandWritten: Event {
        static let name = "Order Completed"
    }

    @Test("A record the plan doesn't describe is left out as unknownEvent even when Iglu doesn't take its name")
    func unknownBeforeInvalidName() throws {
        let sut = try SnowplowBatchEncoder(vendor: "com.example", appID: "shop", plan: try TrackingPlan(schemas: [CheckoutStarted.schema]))
        let record = EventRecord(event: OrderCompleted(), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let expected: [SnowplowEncodingError] = [.unknownEvent(name: "Order Completed", version: 1)]

        let actual = sut.requests(for: [record]).skippedRecords.map(\.reason)

        #expect(actual == expected)
    }

    @Test("A record whose name Iglu doesn't take is left out as invalidSchemaKey, before a timestamp Snowplow can't store")
    func invalidNameBeforeTimestamp() throws {
        let schema = EventSchema(name: "Order Completed", version: 1, consentCategory: .analytics, properties: [])
        let sut = try SnowplowBatchEncoder(vendor: "com.example", appID: "shop", plan: try TrackingPlan(schemas: [schema]))
        let record = EventRecord(event: OrderCompleted(), timestamp: Date(timeIntervalSince1970: .nan), sourceLocation: nil)
        let expected: [SnowplowEncodingError] = [.invalidSchemaKey(name: "Order Completed", version: 1)]

        let actual = sut.requests(for: [record]).skippedRecords.map(\.reason)

        #expect(actual == expected)
    }

    @Test("A record whose event isn't Encodable is left out as notEncodable")
    func notEncodable() throws {
        let handWritten = EventSchema(name: "HandWritten", version: 1, consentCategory: .analytics, properties: [EventSchema.Property(name: "plan", typeName: "String", isOptional: false)])
        let sut = try SnowplowBatchEncoder(vendor: "com.example", appID: "shop", plan: try TrackingPlan(schemas: [handWritten]))
        let record = EventRecord(event: HandWritten(plan: "pro"), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let expected = [SkippedRecord<SnowplowEncodingError>(recordID: record.id, eventName: "HandWritten", schemaVersion: 1, reason: .notEncodable(name: "HandWritten"))]

        let actual = sut.requests(for: [record]).skippedRecords

        #expect(actual == expected)
    }

    @Test("A record holding a NaN is left out as unrepresentableValue, naming the property")
    func unrepresentableValue() throws {
        let sut = try SnowplowBatchEncoder(vendor: "com.example", appID: "shop", plan: try TrackingPlan(schemas: [Measured.schema]))
        let record = EventRecord(event: Measured(value: .nan), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let expected = [SkippedRecord<SnowplowEncodingError>(recordID: record.id, eventName: "measured", schemaVersion: 1, reason: .unrepresentableValue(event: "measured", property: "value"))]

        let actual = sut.requests(for: [record]).skippedRecords

        #expect(actual == expected)
    }

    @Test("A record whose encoding isn't a map is left out as unrepresentableValue with no property")
    func notAMap() throws {
        let schema = EventSchema(name: "not_a_map", version: 1, consentCategory: .analytics, properties: [])
        let sut = try SnowplowBatchEncoder(vendor: "com.example", appID: "shop", plan: try TrackingPlan(schemas: [schema]))
        let record = EventRecord(event: NotAMap(), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let expected = SnowplowEncodingError.unrepresentableValue(event: "not_a_map", property: "")

        let actual = sut.requests(for: [record])

        #expect(actual.requests.isEmpty)
        #expect(actual.skippedRecords.map(\.reason) == [expected])
    }

    // Snowplow's enrichment fails a timestamp outside the years 0 to 9999 (Enrich 6.15.0,
    // EventEnrichments.extractTimestamp). 0000-01-01T00:00:00Z is -62,167,219,200 seconds from
    // 1970, and 10000-01-01T00:00:00Z is 253,402,300,800.
    @Test("A record whose timestamp is outside the years 0 to 9999 is left out as unrepresentableTimestamp, and one just inside is sent", arguments: [
        (Double.nan, true), (.infinity, true), (-.infinity, true), (-62_167_219_200.001, true), (253_402_300_800, true),
        (9.3e15, true), (-62_167_219_200, false), (253_402_300_799.999, false), (0, false), (-1, false), (1_795_442_607, false),
    ])
    func unrepresentableTimestamp(seconds: Double, skipped: Bool) throws {
        let sut = try SnowplowBatchEncoder(vendor: "com.example", appID: "shop", plan: try TrackingPlan(schemas: [CheckoutStarted.schema]))
        let record = EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: seconds), sourceLocation: nil)
        let expected: [SkippedRecord<SnowplowEncodingError>] = skipped
            ? [SkippedRecord(recordID: record.id, eventName: "checkout_started", schemaVersion: 2, reason: .unrepresentableTimestamp)]
            : []

        let actual = sut.requests(for: [record])

        #expect(actual.skippedRecords == expected)
        #expect(actual.requests.flatMap(\.recordIDs) == (skipped ? [] : [record.id]))
    }

    @Test("A batch whose every record is skipped has no request, and each record's reason is reported in order")
    func everyRecordSkipped() throws {
        let orderCompleted = EventSchema(name: "Order Completed", version: 1, consentCategory: .analytics, properties: [])
        let sut = try SnowplowBatchEncoder(vendor: "com.example", appID: "shop", plan: try TrackingPlan(schemas: [CheckoutStarted.schema, Measured.schema, orderCompleted]))
        let batch = [
            EventRecord(event: HandWritten(plan: "pro"), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil),
            EventRecord(event: OrderCompleted(), timestamp: Date(timeIntervalSince1970: 1_795_442_608), sourceLocation: nil),
            EventRecord(event: Measured(value: .infinity), timestamp: Date(timeIntervalSince1970: 1_795_442_609), sourceLocation: nil),
            EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: .nan), sourceLocation: nil),
        ]
        let expectedSkipped = [
            SkippedRecord<SnowplowEncodingError>(recordID: batch[0].id, eventName: "HandWritten", schemaVersion: 1, reason: .unknownEvent(name: "HandWritten", version: 1)),
            SkippedRecord<SnowplowEncodingError>(recordID: batch[1].id, eventName: "Order Completed", schemaVersion: 1, reason: .invalidSchemaKey(name: "Order Completed", version: 1)),
            SkippedRecord<SnowplowEncodingError>(recordID: batch[2].id, eventName: "measured", schemaVersion: 1, reason: .unrepresentableValue(event: "measured", property: "value")),
            SkippedRecord<SnowplowEncodingError>(recordID: batch[3].id, eventName: "checkout_started", schemaVersion: 2, reason: .unrepresentableTimestamp),
        ]

        let actual = sut.requests(for: batch)

        #expect(actual.requests.isEmpty)
        #expect(actual.skippedRecords == expectedSkipped)
    }

    @Test("An event too large for a request of it alone is left out as oversized, with its byte count, and the rest are sent")
    func oversized() throws {
        let label = EventSchema(name: "labelled", version: 1, consentCategory: .analytics, properties: [EventSchema.Property(name: "label", typeName: "String", isOptional: false)])
        let limit = try BatchLimit(maximumRecordCount: 25, maximumByteCount: 600, maximumRecordByteCount: 600)
        let sut = try SnowplowBatchEncoder(vendor: "com.example", appID: "shop", plan: try TrackingPlan(schemas: [label]), limit: limit)
        let large = EventRecord(event: Labelled(label: String(repeating: "x", count: 600)), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let small = EventRecord(event: Labelled(label: "x"), timestamp: Date(timeIntervalSince1970: 1_795_442_608), sourceLocation: nil)

        let actual = sut.requests(for: [large, small])

        #expect(actual.requests.flatMap(\.recordIDs) == [small.id])
        let reason = try #require(actual.skippedRecords.first?.reason)
        guard case .oversized(let byteCount) = reason else {
            Issue.record("Expected oversized, got \(reason)")
            return
        }
        #expect(byteCount > 600)
        #expect(actual.skippedRecords.map(\.recordID) == [large.id])
    }

    /// An event of one string property, `label`.
    struct Labelled: Event, Codable {
        static let name = "labelled"
        var label: String
    }
}
