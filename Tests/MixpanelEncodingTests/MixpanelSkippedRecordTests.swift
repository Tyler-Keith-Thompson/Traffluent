import EventMacros
import Foundation
import HTTPDestinations
import Instrumentation
import MixpanelEncoding
import Persistence
import Sessions
import Testing
import TrackingPlans

@Suite("MixpanelBatchEncoder: skipped records")
struct MixpanelSkippedRecordTests {
    @Event(name: "checkout_started", version: 2)
    struct CheckoutStarted {
        var cartSize: Int
    }

    @Event(name: "measured")
    struct Measured {
        var value: Double
    }

    @Event(name: "video_watched")
    struct VideoWatched {
        var time: Double
        var token: String
        var ip: String
    }

    @Event(name: "redacted_time")
    struct RedactedTime {
        var time: Sensitive<Double>
        var count: Int
    }

    struct HandWritten: Event {
        var plan: String
    }

    /// An event named by its test, for Mixpanel's reserved names: a task-local, so tests running
    /// in parallel each see their own.
    struct Named: Event, Codable {
        @TaskLocal static var testName = "named"

        static var name: String { testName }

        init() {}
    }

    /// An event with one property of a name its test gives, which only a hand-written `Encodable`
    /// conformance can write when the name isn't a Swift identifier.
    struct PropertyNamed: Event, Encodable {
        static let name = "property_named"

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

        var property: String

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: Key.self)
            try container.encode("value", forKey: Key(stringValue: property))
            try container.encode(1, forKey: Key(stringValue: "count"))
        }
    }

    /// An event named as Mixpanel's identify call.
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
        let sut = MixpanelBatchEncoder(projectToken: "testprojecttoken", plan: try TrackingPlan(schemas: [CheckoutStarted.schema]))
        var context = ServiceContext.topLevel
        context[SessionKey.self] = UUID()
        let skipped = EventRecord(event: Measured(value: 1), timestamp: Date(timeIntervalSince1970: 1_795_442_608), sourceLocation: nil, context: context)
        let batch = [
            EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil, context: context),
            skipped,
            EventRecord(event: CheckoutStarted(cartSize: 3), timestamp: Date(timeIntervalSince1970: 1_795_442_609), sourceLocation: nil, context: context),
        ]
        let expectedBody = try #require(sut.requests(for: [batch[0], batch[2]]).requests.first).body
        let expectedSkipped = [SkippedRecord<MixpanelEncodingError>(recordID: skipped.id, eventName: "measured", schemaVersion: 1, reason: .unknownEvent(name: "measured", version: 1))]

        let actual = sut.requests(for: batch)

        #expect(actual.requests.map(\.body) == [expectedBody])
        #expect(actual.skippedRecords == expectedSkipped)
    }

    @Test("A record whose version the plan doesn't describe is left out as unknownEvent with its version, though the plan has its name")
    func unknownVersion() throws {
        let earlier = EventSchema(name: "checkout_started", version: 1, consentCategory: .analytics, properties: [])
        let sut = MixpanelBatchEncoder(projectToken: "testprojecttoken", plan: try TrackingPlan(schemas: [earlier]))
        let record = EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let expected = [SkippedRecord<MixpanelEncodingError>(recordID: record.id, eventName: "checkout_started", schemaVersion: 2, reason: .unknownEvent(name: "checkout_started", version: 2))]

        let actual = sut.requests(for: [record]).skippedRecords

        #expect(actual == expected)
    }

    @Test("A record whose event isn't Encodable is left out as notEncodable")
    func notEncodable() throws {
        let handWritten = EventSchema(name: "HandWritten", version: 1, consentCategory: .analytics, properties: [EventSchema.Property(name: "plan", typeName: "String", isOptional: false)])
        let sut = MixpanelBatchEncoder(projectToken: "testprojecttoken", plan: try TrackingPlan(schemas: [handWritten]))
        let record = EventRecord(event: HandWritten(plan: "pro"), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let expected = [SkippedRecord<MixpanelEncodingError>(recordID: record.id, eventName: "HandWritten", schemaVersion: 1, reason: .notEncodable(name: "HandWritten"))]

        let actual = sut.requests(for: [record]).skippedRecords

        #expect(actual == expected)
    }

    @Test("A record holding a NaN is left out as unrepresentableValue, naming the property")
    func unrepresentableValue() throws {
        let sut = MixpanelBatchEncoder(projectToken: "testprojecttoken", plan: try TrackingPlan(schemas: [Measured.schema]))
        let record = EventRecord(event: Measured(value: .nan), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let expected = [SkippedRecord<MixpanelEncodingError>(recordID: record.id, eventName: "measured", schemaVersion: 1, reason: .unrepresentableValue(event: "measured", property: "value"))]

        let actual = sut.requests(for: [record]).skippedRecords

        #expect(actual == expected)
    }

    @Test("A record whose encoding isn't a map is left out as unrepresentableValue with no property")
    func notAMap() throws {
        let schema = EventSchema(name: "not_a_map", version: 1, consentCategory: .analytics, properties: [])
        let sut = MixpanelBatchEncoder(projectToken: "testprojecttoken", plan: try TrackingPlan(schemas: [schema]))
        let record = EventRecord(event: NotAMap(), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let expected = MixpanelEncodingError.unrepresentableValue(event: "not_a_map", property: "")

        let actual = sut.requests(for: [record])

        #expect(actual.requests.isEmpty)
        #expect(actual.skippedRecords.map(\.reason) == [expected])
    }

    // Mixpanel's own events are named with a leading $ ($identify, $create_alias, $merge,
    // $mp_web_page_view).
    @Test("A record whose event name starts with $ is left out as reservedEventName, and names that only resemble one are sent", arguments: [
        ("$identify", true), ("$create_alias", true), ("$merge", true), ("$mp_web_page_view", true), ("$", true), ("$signed_up", true),
        ("identify", false), (" $identify", false), ("signed_up$", false), ("mp_page_view", false), ("Identify", false),
    ])
    func reservedEventName(name: String, reserved: Bool) throws {
        try Named.$testName.withValue(name) {
            try check()
        }

        // A nested function rather than the closure's body: AGENTS.md, closures inside #expect
        // inside another closure.
        func check() throws {
            let schema = EventSchema(name: name, version: 1, consentCategory: .analytics, properties: [])
            let sut = MixpanelBatchEncoder(projectToken: "testprojecttoken", plan: try TrackingPlan(schemas: [schema]))
            let record = EventRecord(event: Named(), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
            let expected: [MixpanelEncodingError] = reserved ? [.reservedEventName(name: name)] : []
            let expectedRequestCount = reserved ? 0 : 1

            let actual = sut.requests(for: [record])

            #expect(actual.skippedRecords.map(\.reason) == expected)
            #expect(actual.requests.count == expectedRequestCount)
        }
    }

    @Test("A record whose event name Mixpanel reserves is left out, and the records around it are sent")
    func reservedAmongOthers() throws {
        let identify = EventSchema(name: "$identify", version: 1, consentCategory: .analytics, properties: [])
        let sut = MixpanelBatchEncoder(projectToken: "testprojecttoken", plan: try TrackingPlan(schemas: [CheckoutStarted.schema, identify]))
        let skipped = EventRecord(event: Identify(), timestamp: Date(timeIntervalSince1970: 1_795_442_608), sourceLocation: nil)
        let batch = [
            EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil),
            skipped,
            EventRecord(event: CheckoutStarted(cartSize: 3), timestamp: Date(timeIntervalSince1970: 1_795_442_609), sourceLocation: nil),
        ]
        let expectedBody = try #require(sut.requests(for: [batch[0], batch[2]]).requests.first).body
        let expectedSkipped = [SkippedRecord<MixpanelEncodingError>(recordID: skipped.id, eventName: "$identify", schemaVersion: 1, reason: .reservedEventName(name: "$identify"))]

        let actual = sut.requests(for: batch)

        #expect(actual.requests.map(\.body) == [expectedBody])
        #expect(actual.skippedRecords == expectedSkipped)
    }

    @Test("A record the plan describes whose name Mixpanel reserves is left out as reservedEventName, though it can't be read either")
    func reservedBeforeReadError() throws {
        struct CreateAlias: Event {
            static let name = "$create_alias"
        }
        let schema = EventSchema(name: "$create_alias", version: 1, consentCategory: .analytics, properties: [])
        let sut = MixpanelBatchEncoder(projectToken: "testprojecttoken", plan: try TrackingPlan(schemas: [schema]))
        let record = EventRecord(event: CreateAlias(), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let expected = [SkippedRecord<MixpanelEncodingError>(recordID: record.id, eventName: "$create_alias", schemaVersion: 1, reason: .reservedEventName(name: "$create_alias"))]

        let actual = sut.requests(for: [record]).skippedRecords

        #expect(actual == expected)
    }

    @Test("A record the plan doesn't describe is left out as unknownEvent even when Mixpanel reserves its name")
    func unknownBeforeReserved() throws {
        let sut = MixpanelBatchEncoder(projectToken: "testprojecttoken", plan: try TrackingPlan(schemas: []))
        let record = EventRecord(event: Identify(), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let expected = [SkippedRecord<MixpanelEncodingError>(recordID: record.id, eventName: "$identify", schemaVersion: 1, reason: .unknownEvent(name: "$identify", version: 1))]

        let actual = sut.requests(for: [record]).skippedRecords

        #expect(actual == expected)
    }

    // Mixpanel's reserved event properties
    // (https://docs.mixpanel.com/docs/data-structure/property-reference/reserved-properties), and
    // the names the encoder writes beside the event's.
    @Test("A record with a property Mixpanel reads for itself is left out as reservedPropertyName, and names that only resemble one are sent", arguments: [
        ("$ignore", true), ("$insert_id", true), ("$user_id", true), ("$device_id", true), ("$os", true), ("$", true), ("token", true),
        ("time", true), ("distinct_id", true), ("ip", true), ("bucket", true),
        ("Token", false), ("Time", false), ("times", false), ("distinctID", false), ("ip_address", false), ("buckets", false), ("user_id", false),
        ("insert_id", false), ("device_id", false), ("mp_lib", false), ("x$", false), (" $ignore", false),
    ])
    func reservedPropertyName(property: String, reserved: Bool) throws {
        let schema = EventSchema(name: "property_named", version: 1, consentCategory: .analytics, properties: [])
        let sut = MixpanelBatchEncoder(projectToken: "testprojecttoken", plan: try TrackingPlan(schemas: [schema]))
        let record = EventRecord(event: PropertyNamed(property: property), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let expected: [MixpanelEncodingError] = reserved ? [.reservedPropertyName(event: "property_named", property: property)] : []
        let expectedRequestCount = reserved ? 0 : 1

        let actual = sut.requests(for: [record])

        #expect(actual.skippedRecords.map(\.reason) == expected)
        #expect(actual.requests.count == expectedRequestCount)
    }

    @Test("An @Event with properties named time, token and ip is left out, naming the first of them by its bytes, so none is lost or replaced")
    func reservedEventProperties() throws {
        let sut = MixpanelBatchEncoder(projectToken: "testprojecttoken", plan: try TrackingPlan(schemas: [VideoWatched.schema, CheckoutStarted.schema]))
        let skipped = EventRecord(event: VideoWatched(time: 12.5, token: "abc", ip: "x"), timestamp: Date(timeIntervalSince1970: 1_795_442_608), sourceLocation: nil)
        let sent = EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let expected = [SkippedRecord<MixpanelEncodingError>(recordID: skipped.id, eventName: "video_watched", schemaVersion: 1, reason: .reservedPropertyName(event: "video_watched", property: "ip"))]

        let actual = sut.requests(for: [sent, skipped])

        #expect(actual.skippedRecords == expected)
        #expect(actual.requests.flatMap(\.recordIDs) == [sent.id])
    }

    @Test("A Sensitive property named as a reserved one is never sent, so the record is sent without it")
    func reservedSensitiveProperty() throws {
        let sut = MixpanelBatchEncoder(projectToken: "testprojecttoken", plan: try TrackingPlan(schemas: [RedactedTime.schema]))
        let record = EventRecord(event: RedactedTime(time: Sensitive(12.5), count: 1), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let expectedTime: Int64 = 1_795_442_607_000

        let actual = sut.requests(for: [record])

        let body = try #require(actual.requests.first).body.body
        let event = try #require((try JSONSerialization.jsonObject(with: body) as? [[String: Any]])?.first)
        let time = ((event["properties"] as? [String: Any])?["time"] as? NSNumber)?.int64Value
        #expect(actual.skippedRecords.isEmpty)
        #expect(time == expectedTime)
        #expect(!String(decoding: body, as: UTF8.self).contains("12.5"))
    }

    @Test("A record whose name Mixpanel reserves is left out as reservedEventName, before a reserved property")
    func reservedNameBeforeReservedProperty() throws {
        struct IdentifyWithToken: Event, Codable {
            static let name = "$identify"
            var token: String
        }
        let schema = EventSchema(name: "$identify", version: 1, consentCategory: .analytics, properties: [])
        let sut = MixpanelBatchEncoder(projectToken: "testprojecttoken", plan: try TrackingPlan(schemas: [schema]))
        let record = EventRecord(event: IdentifyWithToken(token: "x"), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let expected: [MixpanelEncodingError] = [.reservedEventName(name: "$identify")]

        let actual = sut.requests(for: [record]).skippedRecords.map(\.reason)

        #expect(actual == expected)
    }

    @Test("A record with a reserved property is left out as reservedPropertyName, before a timestamp Mixpanel can't take")
    func reservedPropertyBeforeTimestamp() throws {
        let sut = MixpanelBatchEncoder(projectToken: "testprojecttoken", plan: try TrackingPlan(schemas: [VideoWatched.schema]))
        let record = EventRecord(event: VideoWatched(time: 1, token: "abc", ip: "x"), timestamp: Date(timeIntervalSince1970: .nan), sourceLocation: nil)
        let expected: [MixpanelEncodingError] = [.reservedPropertyName(event: "video_watched", property: "ip")]

        let actual = sut.requests(for: [record]).skippedRecords.map(\.reason)

        #expect(actual == expected)
    }

    // Int64.max milliseconds is about 9.223e15 seconds from 1970, and 1971-01-01 is 31,536,000
    // seconds after it.
    @Test("A record whose timestamp is before 1971 or has no epoch-milliseconds form is left out as unrepresentableTimestamp, and one just inside the range is sent", arguments: [
        (Double.nan, true), (.infinity, true), (-.infinity, true), (9.3e15, true), (-9.3e15, true), (0, true), (-1, true),
        (31_535_999.999, true), (31_536_000, false), (9.2e15, false), (1_795_442_607, false),
    ])
    func unrepresentableTimestamp(seconds: Double, skipped: Bool) throws {
        let sut = MixpanelBatchEncoder(projectToken: "testprojecttoken", plan: try TrackingPlan(schemas: [CheckoutStarted.schema]))
        let record = EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: seconds), sourceLocation: nil)
        let expected: [SkippedRecord<MixpanelEncodingError>] = skipped
            ? [SkippedRecord(recordID: record.id, eventName: "checkout_started", schemaVersion: 2, reason: .unrepresentableTimestamp)]
            : []

        let actual = sut.requests(for: [record])

        #expect(actual.skippedRecords == expected)
        #expect(actual.requests.flatMap(\.recordIDs) == (skipped ? [] : [record.id]))
    }

    @Test("A batch whose every record is skipped has no request, and each record's reason is reported in order")
    func everyRecordSkipped() throws {
        let identify = EventSchema(name: "$identify", version: 1, consentCategory: .analytics, properties: [])
        let sut = MixpanelBatchEncoder(projectToken: "testprojecttoken", plan: try TrackingPlan(schemas: [CheckoutStarted.schema, VideoWatched.schema, identify]))
        let batch = [
            EventRecord(event: Measured(value: 1), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil),
            EventRecord(event: Identify(), timestamp: Date(timeIntervalSince1970: 1_795_442_608), sourceLocation: nil),
            EventRecord(event: VideoWatched(time: 1, token: "abc", ip: "x"), timestamp: Date(timeIntervalSince1970: 1_795_442_609), sourceLocation: nil),
            EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: .nan), sourceLocation: nil),
        ]
        let expectedSkipped = [
            SkippedRecord<MixpanelEncodingError>(recordID: batch[0].id, eventName: "measured", schemaVersion: 1, reason: .unknownEvent(name: "measured", version: 1)),
            SkippedRecord<MixpanelEncodingError>(recordID: batch[1].id, eventName: "$identify", schemaVersion: 1, reason: .reservedEventName(name: "$identify")),
            SkippedRecord<MixpanelEncodingError>(recordID: batch[2].id, eventName: "video_watched", schemaVersion: 1, reason: .reservedPropertyName(event: "video_watched", property: "ip")),
            SkippedRecord<MixpanelEncodingError>(recordID: batch[3].id, eventName: "checkout_started", schemaVersion: 2, reason: .unrepresentableTimestamp),
        ]

        let actual = sut.requests(for: batch)

        #expect(actual.requests.isEmpty)
        #expect(actual.skippedRecords == expectedSkipped)
    }
}
