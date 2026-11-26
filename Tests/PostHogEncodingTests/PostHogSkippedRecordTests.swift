import EventMacros
import Foundation
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
    struct Identify: Event, BinaryCodable {
        static let name = "$identify"

        init() {}

        func encode(to encoder: inout BinaryEncoder) {
            encoder.encodeMap { _ in }
        }

        init(from decoder: inout BinaryDecoder) throws(BinaryDecodingError) {}
    }

    /// Encodes as a bare integer rather than a map of its properties.
    struct NotAMap: Event, BinaryCodable {
        static let name = "not_a_map"

        init() {}

        func encode(to encoder: inout BinaryEncoder) {
            encoder.encode(1)
        }

        init(from decoder: inout BinaryDecoder) throws(BinaryDecodingError) {}
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
        let expectedBody = try sut.encode([batch[0], batch[2]])
        let expectedSkipped = [PostHogSkippedRecord(recordID: skipped.id, eventName: "measured", schemaVersion: 1, reason: .unknownEvent(name: "measured", version: 1))]

        let actual = sut.batch(of: batch)

        #expect(actual.body == expectedBody)
        #expect(actual.skippedRecords == expectedSkipped)
    }

    @Test("A record whose version the plan doesn't describe is left out as unknownEvent with its version, though the plan has its name")
    func unknownVersion() throws {
        let earlier = EventSchema(name: "checkout_started", version: 1, consentCategory: .analytics, properties: [])
        let sut = PostHogBatchEncoder(projectToken: "phc_test", plan: try TrackingPlan(schemas: [earlier]))
        var context = ServiceContext.topLevel
        context[SessionKey.self] = UUID()
        let record = EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil, context: context)
        let expected = [PostHogSkippedRecord(recordID: record.id, eventName: "checkout_started", schemaVersion: 2, reason: .unknownEvent(name: "checkout_started", version: 2))]

        let actual = sut.batch(of: [record]).skippedRecords

        #expect(actual == expected)
    }

    @Test("A record whose event isn't BinaryCodable is left out as notBinaryCodable")
    func notBinaryCodable() throws {
        let handWritten = EventSchema(name: "HandWritten", version: 1, consentCategory: .analytics, properties: [EventSchema.Property(name: "plan", typeName: "String", isOptional: false)])
        let sut = PostHogBatchEncoder(projectToken: "phc_test", plan: try TrackingPlan(schemas: [handWritten]))
        var context = ServiceContext.topLevel
        context[SessionKey.self] = UUID()
        let record = EventRecord(event: HandWritten(plan: "pro"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil, context: context)
        let expected = [PostHogSkippedRecord(recordID: record.id, eventName: "HandWritten", schemaVersion: 1, reason: .notBinaryCodable(name: "HandWritten"))]

        let actual = sut.batch(of: [record]).skippedRecords

        #expect(actual == expected)
    }

    @Test("A record holding a NaN is left out as unrepresentableValue, naming the property")
    func unrepresentableValue() throws {
        let sut = PostHogBatchEncoder(projectToken: "phc_test", plan: try TrackingPlan(schemas: [Measured.schema]))
        var context = ServiceContext.topLevel
        context[SessionKey.self] = UUID()
        let record = EventRecord(event: Measured(value: .nan), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil, context: context)
        let expected = [PostHogSkippedRecord(recordID: record.id, eventName: "measured", schemaVersion: 1, reason: .unrepresentableValue(event: "measured", property: "value"))]

        let actual = sut.batch(of: [record]).skippedRecords

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

        #expect(throws: expected) {
            try sut.encode([record])
        }
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
        let expectedBody = try sut.encode([batch[0], batch[2]])
        let expectedSkipped = [PostHogSkippedRecord(recordID: skipped.id, eventName: "$identify", schemaVersion: 1, reason: .reservedEventName(name: "$identify"))]

        let actual = sut.batch(of: batch)

        #expect(actual.body == expectedBody)
        #expect(actual.skippedRecords == expectedSkipped)
    }

    @Test("A record the plan doesn't describe is left out as unknownEvent even when its name starts with $")
    func unknownBeforeReserved() throws {
        let sut = PostHogBatchEncoder(projectToken: "phc_test", plan: try TrackingPlan(schemas: []))
        let record = EventRecord(event: Identify(), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)
        let expected = [PostHogSkippedRecord(recordID: record.id, eventName: "$identify", schemaVersion: 1, reason: .unknownEvent(name: "$identify", version: 1))]

        let actual = sut.batch(of: [record]).skippedRecords

        #expect(actual == expected)
    }

    @Test("A batch whose every record is skipped has no body, and encode throws the first record's reason")
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
            PostHogSkippedRecord(recordID: batch[0].id, eventName: "measured", schemaVersion: 1, reason: .unknownEvent(name: "measured", version: 1)),
            PostHogSkippedRecord(recordID: batch[1].id, eventName: "$identify", schemaVersion: 1, reason: .reservedEventName(name: "$identify")),
        ]
        let expectedError = PostHogEncodingError.unknownEvent(name: "measured", version: 1)

        let actual = sut.batch(of: batch)

        #expect(actual.body == nil)
        #expect(actual.skippedRecords == expectedSkipped)
        #expect(throws: expectedError) {
            try sut.encode(batch)
        }
    }
}
