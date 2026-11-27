import EventMacros
import Foundation
import HTTPDestinations
import Instrumentation
import Persistence
import PostHogEncoding
import Sessions
import Testing
import TrackingPlans

@Suite("PostHogBatchEncoder: skipped records")
struct PostHogSkippedRecordTests {
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

    /// An event named as one of PostHog's own.
    struct Identify: Event, Codable {
        static let name = "$identify"

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
        let sut = PostHogBatchEncoder(projectToken: "phc_test", plan: try TrackingPlan(schemas: [CheckoutStarted.schema]))
        var context = ServiceContext.topLevel
        context[SessionKey.self] = UUID()
        let skipped = EventRecord(event: Measured(value: 1), timestamp: Date(timeIntervalSince1970: 1), sourceLocation: nil, context: context)
        let batch = [
            EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil, context: context),
            skipped,
            EventRecord(event: CheckoutStarted(cartSize: 3), timestamp: Date(timeIntervalSince1970: 2), sourceLocation: nil, context: context),
        ]
        let expectedBody = try #require(sut.requests(for: [batch[0], batch[2]]).requests.first).body
        let expectedSkipped = [SkippedRecord<PostHogEncodingError>(recordID: skipped.id, eventName: "measured", schemaVersion: 1, reason: .unknownEvent(name: "measured", version: 1))]

        let actual = sut.requests(for: batch)

        #expect(actual.requests.map(\.body) == [expectedBody])
        #expect(actual.skippedRecords == expectedSkipped)
    }

    @Test("A record whose version the plan doesn't describe is left out as unknownEvent with its version, though the plan has its name")
    func unknownVersion() throws {
        let earlier = EventSchema(name: "checkout_started", version: 1, consentCategory: .analytics, properties: [])
        let sut = PostHogBatchEncoder(projectToken: "phc_test", plan: try TrackingPlan(schemas: [earlier]))
        var context = ServiceContext.topLevel
        context[SessionKey.self] = UUID()
        let record = EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil, context: context)
        let expected = [SkippedRecord<PostHogEncodingError>(recordID: record.id, eventName: "checkout_started", schemaVersion: 2, reason: .unknownEvent(name: "checkout_started", version: 2))]

        let actual = sut.requests(for: [record]).skippedRecords

        #expect(actual == expected)
    }

    @Test("A record whose event isn't Encodable is left out as notEncodable")
    func notEncodable() throws {
        let handWritten = EventSchema(name: "HandWritten", version: 1, consentCategory: .analytics, properties: [EventSchema.Property(name: "plan", typeName: "String", isOptional: false)])
        let sut = PostHogBatchEncoder(projectToken: "phc_test", plan: try TrackingPlan(schemas: [handWritten]))
        var context = ServiceContext.topLevel
        context[SessionKey.self] = UUID()
        let record = EventRecord(event: HandWritten(plan: "pro"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil, context: context)
        let expected = [SkippedRecord<PostHogEncodingError>(recordID: record.id, eventName: "HandWritten", schemaVersion: 1, reason: .notEncodable(name: "HandWritten"))]

        let actual = sut.requests(for: [record]).skippedRecords

        #expect(actual == expected)
    }

    @Test("A record holding a NaN is left out as unrepresentableValue, naming the property")
    func unrepresentableValue() throws {
        let sut = PostHogBatchEncoder(projectToken: "phc_test", plan: try TrackingPlan(schemas: [Measured.schema]))
        var context = ServiceContext.topLevel
        context[SessionKey.self] = UUID()
        let record = EventRecord(event: Measured(value: .nan), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil, context: context)
        let expected = [SkippedRecord<PostHogEncodingError>(recordID: record.id, eventName: "measured", schemaVersion: 1, reason: .unrepresentableValue(event: "measured", property: "value"))]

        let actual = sut.requests(for: [record]).skippedRecords

        #expect(actual == expected)
    }

    // 2^63 milliseconds is about 9.223e15 seconds from 1970; each boundary is pinned at the last
    // Double that throws and the first that doesn't.
    static let timestampBoundaries: [(seconds: Double, skipped: Bool)] = [
        (.nan, true), (.infinity, true), (-.infinity, true), (0x1p63 / 1000, true), ((0x1p63 / 1000).nextDown, false),
        (-0x1p63 / 1000, false), ((-0x1p63 / 1000).nextDown, true), (0, false),
    ]

    @Test("A record whose timestamp has no ISO 8601 form is left out as unrepresentableTimestamp, and one just inside the range is sent", arguments: timestampBoundaries)
    func unrepresentableTimestamp(seconds: Double, skipped: Bool) throws {
        let sut = PostHogBatchEncoder(projectToken: "phc_test", plan: try TrackingPlan(schemas: [CheckoutStarted.schema]))
        let record = EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: seconds), sourceLocation: nil)
        let expected: [SkippedRecord<PostHogEncodingError>] = skipped
            ? [SkippedRecord(recordID: record.id, eventName: "checkout_started", schemaVersion: 2, reason: .unrepresentableTimestamp)]
            : []

        let actual = sut.requests(for: [record])

        #expect(actual.skippedRecords == expected)
        #expect(actual.requests.flatMap(\.recordIDs) == (skipped ? [] : [record.id]))
    }

    @Test("A record whose event name starts with $ is left out as reservedEventName, though its timestamp has no ISO 8601 form either")
    func reservedNameBeforeTimestamp() throws {
        let identify = EventSchema(name: "$identify", version: 1, consentCategory: .analytics, properties: [])
        let sut = PostHogBatchEncoder(projectToken: "phc_test", plan: try TrackingPlan(schemas: [identify]))
        let record = EventRecord(event: Identify(), timestamp: Date(timeIntervalSince1970: .nan), sourceLocation: nil)
        let expected: [PostHogEncodingError] = [.reservedEventName(name: "$identify")]

        let actual = sut.requests(for: [record]).skippedRecords.map(\.reason)

        #expect(actual == expected)
    }

    @Test("A record whose encoding isn't a map is left out as unrepresentableValue with no property")
    func notAMap() throws {
        let schema = EventSchema(name: "not_a_map", version: 1, consentCategory: .analytics, properties: [])
        let sut = PostHogBatchEncoder(projectToken: "phc_test", plan: try TrackingPlan(schemas: [schema]))
        var context = ServiceContext.topLevel
        context[SessionKey.self] = UUID()
        let record = EventRecord(event: NotAMap(), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil, context: context)
        let expected = PostHogEncodingError.unrepresentableValue(event: "not_a_map", property: "")

        let actual = sut.requests(for: [record])

        #expect(actual.requests.isEmpty)
        #expect(actual.skippedRecords.map(\.reason) == [expected])
    }

    @Test("A record whose event name starts with $ is left out as reservedEventName, and the records around it are sent")
    func reservedEventName() throws {
        let identify = EventSchema(name: "$identify", version: 1, consentCategory: .analytics, properties: [])
        let sut = PostHogBatchEncoder(projectToken: "phc_test", plan: try TrackingPlan(schemas: [CheckoutStarted.schema, identify]))
        var context = ServiceContext.topLevel
        context[SessionKey.self] = UUID()
        let skipped = EventRecord(event: Identify(), timestamp: Date(timeIntervalSince1970: 1), sourceLocation: nil, context: context)
        let batch = [
            EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil, context: context),
            skipped,
            EventRecord(event: CheckoutStarted(cartSize: 3), timestamp: Date(timeIntervalSince1970: 2), sourceLocation: nil, context: context),
        ]
        let expectedBody = try #require(sut.requests(for: [batch[0], batch[2]]).requests.first).body
        let expectedSkipped = [SkippedRecord<PostHogEncodingError>(recordID: skipped.id, eventName: "$identify", schemaVersion: 1, reason: .reservedEventName(name: "$identify"))]

        let actual = sut.requests(for: batch)

        #expect(actual.requests.map(\.body) == [expectedBody])
        #expect(actual.skippedRecords == expectedSkipped)
    }

    @Test("A record the plan describes whose name starts with $ is left out as reservedEventName, though it can't be read either")
    func reservedBeforeReadError() throws {
        struct Screen: Event {
            static let name = "$screen"
        }
        let screen = EventSchema(name: "$screen", version: 1, consentCategory: .analytics, properties: [])
        let sut = PostHogBatchEncoder(projectToken: "phc_test", plan: try TrackingPlan(schemas: [screen]))
        let record = EventRecord(event: Screen(), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)
        let expected = [SkippedRecord<PostHogEncodingError>(recordID: record.id, eventName: "$screen", schemaVersion: 1, reason: .reservedEventName(name: "$screen"))]

        let actual = sut.requests(for: [record]).skippedRecords

        #expect(actual == expected)
    }

    @Test("A record the plan doesn't describe is left out as unknownEvent even when its name starts with $")
    func unknownBeforeReserved() throws {
        let sut = PostHogBatchEncoder(projectToken: "phc_test", plan: try TrackingPlan(schemas: []))
        let record = EventRecord(event: Identify(), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)
        let expected = [SkippedRecord<PostHogEncodingError>(recordID: record.id, eventName: "$identify", schemaVersion: 1, reason: .unknownEvent(name: "$identify", version: 1))]

        let actual = sut.requests(for: [record]).skippedRecords

        #expect(actual == expected)
    }

    @Test("A batch whose every record is skipped has no request, and encode throws the first record's reason")
    func everyRecordSkipped() throws {
        let identify = EventSchema(name: "$identify", version: 1, consentCategory: .analytics, properties: [])
        let sut = PostHogBatchEncoder(projectToken: "phc_test", plan: try TrackingPlan(schemas: [CheckoutStarted.schema, identify]))
        var context = ServiceContext.topLevel
        context[SessionKey.self] = UUID()
        let batch = [
            EventRecord(event: Measured(value: 1), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil, context: context),
            EventRecord(event: Identify(), timestamp: Date(timeIntervalSince1970: 1), sourceLocation: nil, context: context),
        ]
        let expectedSkipped = [
            SkippedRecord<PostHogEncodingError>(recordID: batch[0].id, eventName: "measured", schemaVersion: 1, reason: .unknownEvent(name: "measured", version: 1)),
            SkippedRecord<PostHogEncodingError>(recordID: batch[1].id, eventName: "$identify", schemaVersion: 1, reason: .reservedEventName(name: "$identify")),
        ]

        let actual = sut.requests(for: batch)

        #expect(actual.requests.isEmpty)
        #expect(actual.skippedRecords == expectedSkipped)
    }
}
