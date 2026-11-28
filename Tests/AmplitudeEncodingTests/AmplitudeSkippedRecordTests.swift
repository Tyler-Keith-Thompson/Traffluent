import AmplitudeEncoding
import EventMacros
import Foundation
import HTTPDestinations
import Instrumentation
import Persistence
import Sessions
import Testing
import TrackingPlans

// Private: its events share their names with other events of this test target, and @Event
// leaves a private type's events out of the link check of names (DefiningEvents, Limits).
@Suite("AmplitudeBatchEncoder: skipped records")
private struct AmplitudeSkippedRecordTests {
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

    /// An event named by its test, for Amplitude's reserved names: a task-local, so tests running
    /// in parallel each see their own.
    struct Named: Event, Codable {
        @TaskLocal static var testName = "named"

        static var name: String { testName }

        init() {}
    }

    /// An event named as Amplitude's identify call.
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
        let sut = AmplitudeBatchEncoder(apiKey: "test-api-key", plan: try TrackingPlan(schemas: [CheckoutStarted.schema]))
        var context = ServiceContext.topLevel
        context[SessionKey.self] = UUID()
        let skipped = EventRecord(event: Measured(value: 1), timestamp: Date(timeIntervalSince1970: 1), sourceLocation: nil, context: context)
        let batch = [
            EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil, context: context),
            skipped,
            EventRecord(event: CheckoutStarted(cartSize: 3), timestamp: Date(timeIntervalSince1970: 2), sourceLocation: nil, context: context),
        ]
        let expectedBody = try #require(sut.requests(for: [batch[0], batch[2]]).requests.first).body
        let expectedSkipped = [SkippedRecord<AmplitudeEncodingError>(recordID: skipped.id, eventName: "measured", schemaVersion: 1, reason: .unknownEvent(name: "measured", version: 1))]

        let actual = sut.requests(for: batch)

        #expect(actual.requests.map(\.body) == [expectedBody])
        #expect(actual.skippedRecords == expectedSkipped)
    }

    @Test("A record whose version the plan doesn't describe is left out as unknownEvent with its version, though the plan has its name")
    func unknownVersion() throws {
        let earlier = EventSchema(name: "checkout_started", version: 1, consentCategory: .analytics, properties: [])
        let sut = AmplitudeBatchEncoder(apiKey: "test-api-key", plan: try TrackingPlan(schemas: [earlier]))
        let record = EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)
        let expected = [SkippedRecord<AmplitudeEncodingError>(recordID: record.id, eventName: "checkout_started", schemaVersion: 2, reason: .unknownEvent(name: "checkout_started", version: 2))]

        let actual = sut.requests(for: [record]).skippedRecords

        #expect(actual == expected)
    }

    @Test("A record whose event isn't Encodable is left out as notEncodable")
    func notEncodable() throws {
        let handWritten = EventSchema(name: "HandWritten", version: 1, consentCategory: .analytics, properties: [EventSchema.Property(name: "plan", typeName: "String", isOptional: false)])
        let sut = AmplitudeBatchEncoder(apiKey: "test-api-key", plan: try TrackingPlan(schemas: [handWritten]))
        let record = EventRecord(event: HandWritten(plan: "pro"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)
        let expected = [SkippedRecord<AmplitudeEncodingError>(recordID: record.id, eventName: "HandWritten", schemaVersion: 1, reason: .notEncodable(name: "HandWritten"))]

        let actual = sut.requests(for: [record]).skippedRecords

        #expect(actual == expected)
    }

    @Test("A record holding a NaN is left out as unrepresentableValue, naming the property")
    func unrepresentableValue() throws {
        let sut = AmplitudeBatchEncoder(apiKey: "test-api-key", plan: try TrackingPlan(schemas: [Measured.schema]))
        let record = EventRecord(event: Measured(value: .nan), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)
        let expected = [SkippedRecord<AmplitudeEncodingError>(recordID: record.id, eventName: "measured", schemaVersion: 1, reason: .unrepresentableValue(event: "measured", property: "value"))]

        let actual = sut.requests(for: [record]).skippedRecords

        #expect(actual == expected)
    }

    @Test("A record whose encoding isn't a map is left out as unrepresentableValue with no property")
    func notAMap() throws {
        let schema = EventSchema(name: "not_a_map", version: 1, consentCategory: .analytics, properties: [])
        let sut = AmplitudeBatchEncoder(apiKey: "test-api-key", plan: try TrackingPlan(schemas: [schema]))
        let record = EventRecord(event: NotAMap(), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)
        let expected = AmplitudeEncodingError.unrepresentableValue(event: "not_a_map", property: "")

        let actual = sut.requests(for: [record])

        #expect(actual.requests.isEmpty)
        #expect(actual.skippedRecords.map(\.reason) == [expected])
    }

    // Amplitude's HTTP V2 reference, "Event array keys": the [Amplitude] events are its own, and
    // $identify and $groupidentify its identify calls.
    @Test("A record named as one of Amplitude's own events is left out as reservedEventName, and names that only resemble one are sent", arguments: [
        ("[Amplitude] Start Session", true), ("[Amplitude] End Session", true), ("[Amplitude] Revenue", true), ("[Amplitude] Revenue (Verified)", true),
        ("[Amplitude] Revenue (Unverified)", true), ("[Amplitude] Merged User", true), ("[Amplitude]", true), ("$identify", true), ("$groupidentify", true),
        ("[amplitude] Start Session", false), ("Amplitude Start Session", false), (" [Amplitude] Start Session", false), ("$identify2", false), ("$Identify", false),
        ("identify", false), ("$pageview", false), ("$groupIdentify", false),
    ])
    func reservedEventName(name: String, reserved: Bool) throws {
        try Named.$testName.withValue(name) {
            try check()
        }

        // A nested function rather than the closure's body: AGENTS.md, closures inside #expect
        // inside another closure.
        func check() throws {
            let schema = EventSchema(name: name, version: 1, consentCategory: .analytics, properties: [])
            let sut = AmplitudeBatchEncoder(apiKey: "test-api-key", plan: try TrackingPlan(schemas: [schema]))
            let record = EventRecord(event: Named(), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)
            let expected: [AmplitudeEncodingError] = reserved ? [.reservedEventName(name: name)] : []
            let expectedRequestCount = reserved ? 0 : 1

            let actual = sut.requests(for: [record])

            #expect(actual.skippedRecords.map(\.reason) == expected)
            #expect(actual.requests.count == expectedRequestCount)
        }
    }

    @Test("A record whose event name Amplitude reserves is left out, and the records around it are sent")
    func reservedAmongOthers() throws {
        let identify = EventSchema(name: "$identify", version: 1, consentCategory: .analytics, properties: [])
        let sut = AmplitudeBatchEncoder(apiKey: "test-api-key", plan: try TrackingPlan(schemas: [CheckoutStarted.schema, identify]))
        let skipped = EventRecord(event: Identify(), timestamp: Date(timeIntervalSince1970: 1), sourceLocation: nil)
        let batch = [
            EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil),
            skipped,
            EventRecord(event: CheckoutStarted(cartSize: 3), timestamp: Date(timeIntervalSince1970: 2), sourceLocation: nil),
        ]
        let expectedBody = try #require(sut.requests(for: [batch[0], batch[2]]).requests.first).body
        let expectedSkipped = [SkippedRecord<AmplitudeEncodingError>(recordID: skipped.id, eventName: "$identify", schemaVersion: 1, reason: .reservedEventName(name: "$identify"))]

        let actual = sut.requests(for: batch)

        #expect(actual.requests.map(\.body) == [expectedBody])
        #expect(actual.skippedRecords == expectedSkipped)
    }

    @Test("A record the plan describes whose name Amplitude reserves is left out as reservedEventName, though it can't be read either")
    func reservedBeforeReadError() throws {
        struct StartSession: Event {
            static let name = "[Amplitude] Start Session"
        }
        let schema = EventSchema(name: "[Amplitude] Start Session", version: 1, consentCategory: .analytics, properties: [])
        let sut = AmplitudeBatchEncoder(apiKey: "test-api-key", plan: try TrackingPlan(schemas: [schema]))
        let record = EventRecord(event: StartSession(), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)
        let expected = [SkippedRecord<AmplitudeEncodingError>(recordID: record.id, eventName: "[Amplitude] Start Session", schemaVersion: 1, reason: .reservedEventName(name: "[Amplitude] Start Session"))]

        let actual = sut.requests(for: [record]).skippedRecords

        #expect(actual == expected)
    }

    @Test("A record the plan doesn't describe is left out as unknownEvent even when Amplitude reserves its name")
    func unknownBeforeReserved() throws {
        let sut = AmplitudeBatchEncoder(apiKey: "test-api-key", plan: try TrackingPlan(schemas: []))
        let record = EventRecord(event: Identify(), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)
        let expected = [SkippedRecord<AmplitudeEncodingError>(recordID: record.id, eventName: "$identify", schemaVersion: 1, reason: .unknownEvent(name: "$identify", version: 1))]

        let actual = sut.requests(for: [record]).skippedRecords

        #expect(actual == expected)
    }

    // Int64.max milliseconds is about 9.223e15 seconds from 1970.
    @Test("A record whose timestamp has no epoch-milliseconds form is left out as unrepresentableTimestamp, and one just inside the range is sent", arguments: [
        (Double.nan, true), (.infinity, true), (-.infinity, true), (9.3e15, true), (-9.3e15, true), (9.2e15, false), (-9.2e15, false),
    ])
    func unrepresentableTimestamp(seconds: Double, skipped: Bool) throws {
        let sut = AmplitudeBatchEncoder(apiKey: "test-api-key", plan: try TrackingPlan(schemas: [CheckoutStarted.schema]))
        let record = EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: seconds), sourceLocation: nil)
        let expected: [SkippedRecord<AmplitudeEncodingError>] = skipped
            ? [SkippedRecord(recordID: record.id, eventName: "checkout_started", schemaVersion: 2, reason: .unrepresentableTimestamp)]
            : []

        let actual = sut.requests(for: [record])

        #expect(actual.skippedRecords == expected)
        #expect(actual.requests.flatMap(\.recordIDs) == (skipped ? [] : [record.id]))
    }

    @Test("A batch whose every record is skipped has no request, and each record's reason is reported in order")
    func everyRecordSkipped() throws {
        let identify = EventSchema(name: "$identify", version: 1, consentCategory: .analytics, properties: [])
        let sut = AmplitudeBatchEncoder(apiKey: "test-api-key", plan: try TrackingPlan(schemas: [CheckoutStarted.schema, identify]))
        let batch = [
            EventRecord(event: Measured(value: 1), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil),
            EventRecord(event: Identify(), timestamp: Date(timeIntervalSince1970: 1), sourceLocation: nil),
            EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: .nan), sourceLocation: nil),
        ]
        let expectedSkipped = [
            SkippedRecord<AmplitudeEncodingError>(recordID: batch[0].id, eventName: "measured", schemaVersion: 1, reason: .unknownEvent(name: "measured", version: 1)),
            SkippedRecord<AmplitudeEncodingError>(recordID: batch[1].id, eventName: "$identify", schemaVersion: 1, reason: .reservedEventName(name: "$identify")),
            SkippedRecord<AmplitudeEncodingError>(recordID: batch[2].id, eventName: "checkout_started", schemaVersion: 2, reason: .unrepresentableTimestamp),
        ]

        let actual = sut.requests(for: batch)

        #expect(actual.requests.isEmpty)
        #expect(actual.skippedRecords == expectedSkipped)
    }
}
