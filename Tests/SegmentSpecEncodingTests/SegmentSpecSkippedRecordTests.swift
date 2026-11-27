import EventMacros
import Foundation
import HTTPDestinations
import Instrumentation
import Persistence
import SegmentSpecEncoding
import Sessions
import Testing
import TrackingPlans

@Suite("SegmentSpecBatchEncoder: skipped records")
struct SegmentSpecSkippedRecordTests {
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

    /// An event named by its test, for the reserved names: a task-local, so tests running in
    /// parallel each see their own.
    struct Named: Event, Codable {
        @TaskLocal static var testName = "named"

        static var name: String { testName }

        init() {}
    }

    /// An event named as Customer.io's semantic event that deletes the person.
    struct UserDeleted: Event, Codable {
        static let name = "User Deleted"

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
        let sut = SegmentSpecBatchEncoder(plan: try TrackingPlan(schemas: [CheckoutStarted.schema]))
        var context = ServiceContext.topLevel
        context[SessionKey.self] = UUID()
        let skipped = EventRecord(event: Measured(value: 1), timestamp: Date(timeIntervalSince1970: 1_795_442_608), sourceLocation: nil, context: context)
        let batch = [
            EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil, context: context),
            skipped,
            EventRecord(event: CheckoutStarted(cartSize: 3), timestamp: Date(timeIntervalSince1970: 1_795_442_609), sourceLocation: nil, context: context),
        ]
        let expectedBody = try #require(sut.requests(for: [batch[0], batch[2]]).requests.first).body
        let expectedSkipped = [SkippedRecord<SegmentSpecEncodingError>(recordID: skipped.id, eventName: "measured", schemaVersion: 1, reason: .unknownEvent(name: "measured", version: 1))]

        let actual = sut.requests(for: batch)

        #expect(actual.requests.map(\.body) == [expectedBody])
        #expect(actual.skippedRecords == expectedSkipped)
    }

    @Test("A record whose version the plan doesn't describe is left out as unknownEvent with its version, though the plan has its name")
    func unknownVersion() throws {
        let earlier = EventSchema(name: "checkout_started", version: 1, consentCategory: .analytics, properties: [])
        let sut = SegmentSpecBatchEncoder(plan: try TrackingPlan(schemas: [earlier]))
        let record = EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let expected = [SkippedRecord<SegmentSpecEncodingError>(recordID: record.id, eventName: "checkout_started", schemaVersion: 2, reason: .unknownEvent(name: "checkout_started", version: 2))]

        let actual = sut.requests(for: [record]).skippedRecords

        #expect(actual == expected)
    }

    @Test("A record whose event isn't Encodable is left out as notEncodable")
    func notEncodable() throws {
        let handWritten = EventSchema(name: "HandWritten", version: 1, consentCategory: .analytics, properties: [EventSchema.Property(name: "plan", typeName: "String", isOptional: false)])
        let sut = SegmentSpecBatchEncoder(plan: try TrackingPlan(schemas: [handWritten]))
        let record = EventRecord(event: HandWritten(plan: "pro"), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let expected = [SkippedRecord<SegmentSpecEncodingError>(recordID: record.id, eventName: "HandWritten", schemaVersion: 1, reason: .notEncodable(name: "HandWritten"))]

        let actual = sut.requests(for: [record]).skippedRecords

        #expect(actual == expected)
    }

    @Test("A record holding a NaN is left out as unrepresentableValue, naming the property")
    func unrepresentableValue() throws {
        let sut = SegmentSpecBatchEncoder(plan: try TrackingPlan(schemas: [Measured.schema]))
        let record = EventRecord(event: Measured(value: .nan), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let expected = [SkippedRecord<SegmentSpecEncodingError>(recordID: record.id, eventName: "measured", schemaVersion: 1, reason: .unrepresentableValue(event: "measured", property: "value"))]

        let actual = sut.requests(for: [record]).skippedRecords

        #expect(actual == expected)
    }

    @Test("A record whose encoding isn't a map is left out as unrepresentableValue with no property")
    func notAMap() throws {
        let schema = EventSchema(name: "not_a_map", version: 1, consentCategory: .analytics, properties: [])
        let sut = SegmentSpecBatchEncoder(plan: try TrackingPlan(schemas: [schema]))
        let record = EventRecord(event: NotAMap(), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let expected = SegmentSpecEncodingError.unrepresentableValue(event: "not_a_map", property: "")

        let actual = sut.requests(for: [record])

        #expect(actual.requests.isEmpty)
        #expect(actual.skippedRecords.map(\.reason) == [expected])
    }

    // Customer.io's semantic events
    // (https://docs.customer.io/integrations/data-in/semantic-events/cio-journeys/).
    @Test("A record named as a Customer.io semantic event is left out as reservedEventName, and names that only resemble one are sent", arguments: [
        ("User Deleted", true), ("User Suppressed", true), ("User Unsuppressed", true), ("Device Created or Updated", true),
        ("Device Deleted", true), ("Object Deleted", true), ("Relationship Deleted", true), ("Report Delivery Event", true),
        ("user deleted", false), ("User Deleted ", false), (" User Deleted", false), ("UserDeleted", false), ("user_deleted", false),
        ("Delete Person", false), ("Device Created", false), ("Account Deleted", false), ("Order Completed", false), ("Application Opened", false),
    ])
    func reservedEventName(name: String, reserved: Bool) throws {
        try Named.$testName.withValue(name) {
            try check()
        }

        // A nested function rather than the closure's body: AGENTS.md, closures inside #expect
        // inside another closure.
        func check() throws {
            let schema = EventSchema(name: name, version: 1, consentCategory: .analytics, properties: [])
            let sut = SegmentSpecBatchEncoder(plan: try TrackingPlan(schemas: [schema]))
            let record = EventRecord(event: Named(), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
            let expected: [SegmentSpecEncodingError] = reserved ? [.reservedEventName(name: name)] : []
            let expectedRequestCount = reserved ? 0 : 1

            let actual = sut.requests(for: [record])

            #expect(actual.skippedRecords.map(\.reason) == expected)
            #expect(actual.requests.count == expectedRequestCount)
        }
    }

    @Test("A record named as a semantic event is left out, and the records around it are sent")
    func reservedAmongOthers() throws {
        let userDeleted = EventSchema(name: "User Deleted", version: 1, consentCategory: .analytics, properties: [])
        let sut = SegmentSpecBatchEncoder(plan: try TrackingPlan(schemas: [CheckoutStarted.schema, userDeleted]))
        let skipped = EventRecord(event: UserDeleted(), timestamp: Date(timeIntervalSince1970: 1_795_442_608), sourceLocation: nil)
        let batch = [
            EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil),
            skipped,
            EventRecord(event: CheckoutStarted(cartSize: 3), timestamp: Date(timeIntervalSince1970: 1_795_442_609), sourceLocation: nil),
        ]
        let expectedBody = try #require(sut.requests(for: [batch[0], batch[2]]).requests.first).body
        let expectedSkipped = [SkippedRecord<SegmentSpecEncodingError>(recordID: skipped.id, eventName: "User Deleted", schemaVersion: 1, reason: .reservedEventName(name: "User Deleted"))]

        let actual = sut.requests(for: batch)

        #expect(actual.requests.map(\.body) == [expectedBody])
        #expect(actual.skippedRecords == expectedSkipped)
    }

    @Test("A record the plan describes whose name is a semantic event is left out as reservedEventName, though it can't be read either")
    func reservedBeforeReadError() throws {
        struct DeviceDeleted: Event {
            static let name = "Device Deleted"
        }
        let schema = EventSchema(name: "Device Deleted", version: 1, consentCategory: .analytics, properties: [])
        let sut = SegmentSpecBatchEncoder(plan: try TrackingPlan(schemas: [schema]))
        let record = EventRecord(event: DeviceDeleted(), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let expected = [SkippedRecord<SegmentSpecEncodingError>(recordID: record.id, eventName: "Device Deleted", schemaVersion: 1, reason: .reservedEventName(name: "Device Deleted"))]

        let actual = sut.requests(for: [record]).skippedRecords

        #expect(actual == expected)
    }

    @Test("A record the plan doesn't describe is left out as unknownEvent even when its name is a semantic event")
    func unknownBeforeReserved() throws {
        let sut = SegmentSpecBatchEncoder(plan: try TrackingPlan(schemas: []))
        let record = EventRecord(event: UserDeleted(), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let expected = [SkippedRecord<SegmentSpecEncodingError>(recordID: record.id, eventName: "User Deleted", schemaVersion: 1, reason: .unknownEvent(name: "User Deleted", version: 1))]

        let actual = sut.requests(for: [record]).skippedRecords

        #expect(actual == expected)
    }

    @Test("A record named as a semantic event is left out as reservedEventName, before a timestamp with no ISO 8601 form")
    func reservedBeforeTimestamp() throws {
        let schema = EventSchema(name: "User Deleted", version: 1, consentCategory: .analytics, properties: [])
        let sut = SegmentSpecBatchEncoder(plan: try TrackingPlan(schemas: [schema]))
        let record = EventRecord(event: UserDeleted(), timestamp: Date(timeIntervalSince1970: .nan), sourceLocation: nil)
        let expected: [SegmentSpecEncodingError] = [.reservedEventName(name: "User Deleted")]

        let actual = sut.requests(for: [record]).skippedRecords.map(\.reason)

        #expect(actual == expected)
    }

    // 0001-01-01T00:00:00Z is -62,135,596,800 seconds from 1970, and 10000-01-01T00:00:00Z is
    // 253,402,300,800; 1582-10-14T00:00:00Z, the day before the Gregorian reform, is
    // -12,219,379,200.
    @Test("A record whose timestamp has no four-digit-year ISO 8601 form is left out as unrepresentableTimestamp, and one just inside the range is sent", arguments: [
        (Double.nan, true), (.infinity, true), (-.infinity, true), (-62_135_596_800.001, true), (-62_167_219_200, true), (253_402_300_800, true),
        (253_402_300_801, true), (9.3e15, true), (-62_135_596_800, false), (-12_219_379_200, false), (253_402_300_799.999, false), (0, false), (1_795_442_607, false),
    ])
    func unrepresentableTimestamp(seconds: Double, skipped: Bool) throws {
        let sut = SegmentSpecBatchEncoder(plan: try TrackingPlan(schemas: [CheckoutStarted.schema]))
        let record = EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: seconds), sourceLocation: nil)
        let expected: [SkippedRecord<SegmentSpecEncodingError>] = skipped
            ? [SkippedRecord(recordID: record.id, eventName: "checkout_started", schemaVersion: 2, reason: .unrepresentableTimestamp)]
            : []

        let actual = sut.requests(for: [record])

        #expect(actual.skippedRecords == expected)
        #expect(actual.requests.flatMap(\.recordIDs) == (skipped ? [] : [record.id]))
    }

    @Test("A batch whose every record is skipped has no request, and each record's reason is reported in order")
    func everyRecordSkipped() throws {
        let userDeleted = EventSchema(name: "User Deleted", version: 1, consentCategory: .analytics, properties: [])
        let sut = SegmentSpecBatchEncoder(plan: try TrackingPlan(schemas: [CheckoutStarted.schema, Measured.schema, userDeleted]))
        let batch = [
            EventRecord(event: HandWritten(plan: "pro"), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil),
            EventRecord(event: UserDeleted(), timestamp: Date(timeIntervalSince1970: 1_795_442_608), sourceLocation: nil),
            EventRecord(event: Measured(value: .infinity), timestamp: Date(timeIntervalSince1970: 1_795_442_609), sourceLocation: nil),
            EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: .nan), sourceLocation: nil),
        ]
        let expectedSkipped = [
            SkippedRecord<SegmentSpecEncodingError>(recordID: batch[0].id, eventName: "HandWritten", schemaVersion: 1, reason: .unknownEvent(name: "HandWritten", version: 1)),
            SkippedRecord<SegmentSpecEncodingError>(recordID: batch[1].id, eventName: "User Deleted", schemaVersion: 1, reason: .reservedEventName(name: "User Deleted")),
            SkippedRecord<SegmentSpecEncodingError>(recordID: batch[2].id, eventName: "measured", schemaVersion: 1, reason: .unrepresentableValue(event: "measured", property: "value")),
            SkippedRecord<SegmentSpecEncodingError>(recordID: batch[3].id, eventName: "checkout_started", schemaVersion: 2, reason: .unrepresentableTimestamp),
        ]

        let actual = sut.requests(for: batch)

        #expect(actual.requests.isEmpty)
        #expect(actual.skippedRecords == expectedSkipped)
    }
}
