import EventMacros
import Foundation
import HeapEncoding
import HTTPDestinations
import Testing
import TrackingPlans

// Heap's rules are its track API reference's (https://developers.heap.io/reference/track-1, read
// 2026-11-27): an event "Limited to 1024 characters"; each property's key and value "a number or
// string with fewer than 1024 characters"; `user_id`, `session_id` and `screen_name` not to be
// used as keys; an ISO 8601 timestamp. Characters are counted as UTF-16 code units, so an emoji
// outside the Basic Multilingual Plane counts two.
// Private: its events share their names with other events of this test target, and @Event
// leaves a private type's events out of the link check of names (DefiningEvents, Limits).
@Suite("HeapBatchEncoder: skipped records")
private struct HeapSkippedRecordTests {
    @Event(name: "checkout_started", version: 2)
    struct CheckoutStarted {
        var cartSize: Int
    }

    @Event(name: "measured")
    struct Measured {
        var value: Double
    }

    struct Cart: Codable, Hashable {
        var size: Int
    }

    struct HandWritten: Event {
        var plan: String
    }

    /// An event named by its test: a task-local, so tests running in parallel each see their own.
    struct Named: Event, Codable {
        @TaskLocal static var testName = "named"

        static var name: String { testName }

        init() {}
    }

    /// An event named by its test that isn't `Encodable`.
    struct NamedHandWritten: Event {
        static var name: String { Named.testName }
    }

    /// An event of the properties its test gives, by name, which only a hand-written `Encodable`
    /// conformance can write when a name isn't a Swift identifier.
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

        var properties: [String: JSONValue]

        enum JSONValue: Encodable {
            case string(String)
            case object([String: Int])

            func encode(to encoder: any Encoder) throws {
                var container = encoder.singleValueContainer()
                switch self {
                case .string(let value): try container.encode(value)
                case .object(let value): try container.encode(value)
                }
            }
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: Key.self)
            for (name, value) in properties {
                try container.encode(value, forKey: Key(stringValue: name))
            }
        }
    }

    @Test("A record whose event the plan doesn't describe is left out as unknownEvent, and the records around it are sent")
    func unknownEvent() throws {
        let sut = try HeapBatchEncoder(appID: "12343283", plan: try TrackingPlan(schemas: [CheckoutStarted.schema]))
        let skipped = EventRecord(event: Measured(value: 1), timestamp: Date(timeIntervalSince1970: 1_795_442_608), sourceLocation: nil)
        let batch = [
            EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil),
            skipped,
            EventRecord(event: CheckoutStarted(cartSize: 3), timestamp: Date(timeIntervalSince1970: 1_795_442_609), sourceLocation: nil),
        ]
        let expectedBody = try #require(sut.requests(for: [batch[0], batch[2]]).requests.first).body
        let expectedSkipped = [SkippedRecord<HeapEncodingError>(recordID: skipped.id, eventName: "measured", schemaVersion: 1, reason: .unknownEvent(name: "measured", version: 1))]

        let actual = sut.requests(for: batch)

        #expect(actual.requests.map(\.body) == [expectedBody])
        #expect(actual.skippedRecords == expectedSkipped)
    }

    @Test("A record whose version the plan doesn't describe is left out as unknownEvent with its version, though the plan has its name")
    func unknownVersion() throws {
        let earlier = EventSchema(name: "checkout_started", version: 1, consentCategory: .analytics, properties: [])
        let sut = try HeapBatchEncoder(appID: "12343283", plan: try TrackingPlan(schemas: [earlier]))
        let record = EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let expected = [SkippedRecord<HeapEncodingError>(recordID: record.id, eventName: "checkout_started", schemaVersion: 2, reason: .unknownEvent(name: "checkout_started", version: 2))]

        let actual = sut.requests(for: [record]).skippedRecords

        #expect(actual == expected)
    }

    @Test("An event name of 1,024 characters is sent, and one of 1,025 is left out as invalidEventName, counted in UTF-16", arguments: [
        (String(repeating: "e", count: 1_024), false),
        (String(repeating: "e", count: 1_025), true),
        (String(repeating: "😀", count: 512), false),
        (String(repeating: "😀", count: 512) + "e", true),
        (String(repeating: "é", count: 1_024), false),
        ("e", false),
    ])
    func eventNameLength(name: String, skipped: Bool) throws {
        try Named.$testName.withValue(name) {
            let schema = EventSchema(name: name, version: 1, consentCategory: .analytics, properties: [])
            let sut = try HeapBatchEncoder(appID: "12343283", plan: try TrackingPlan(schemas: [schema]))
            let record = EventRecord(event: Named(), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
            let expected: [HeapEncodingError] = skipped ? [.invalidEventName(name: name)] : []

            let actual = sut.requests(for: [record])

            #expect(actual.skippedRecords.map(\.reason) == expected)
            #expect(actual.requests.flatMap(\.recordIDs) == (skipped ? [] : [record.id]))
        }
    }

    @Test("An event name too long is reported before the event's other faults, but after an event the plan doesn't describe")
    func eventNameOrder() throws {
        let name = String(repeating: "e", count: 1_025)
        try Named.$testName.withValue(name) {
            let schema = EventSchema(name: name, version: 1, consentCategory: .analytics, properties: [])
            let sut = try HeapBatchEncoder(appID: "12343283", plan: try TrackingPlan(schemas: [schema]))
            let other = try HeapBatchEncoder(appID: "12343283", plan: try TrackingPlan(schemas: []))
            let record = EventRecord(event: NamedHandWritten(), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
            let expected: [HeapEncodingError] = [.invalidEventName(name: name)]
            let expectedUnknown: [HeapEncodingError] = [.unknownEvent(name: name, version: 1)]

            let actual = sut.requests(for: [record]).skippedRecords.map(\.reason)
            let actualUnknown = other.requests(for: [record]).skippedRecords.map(\.reason)

            #expect(actual == expected)
            #expect(actualUnknown == expectedUnknown)
        }
    }

    @Test("A property named user_id, session_id or screen_name is left out as reservedPropertyName, and a name like one is sent", arguments: [
        ("user_id", true), ("session_id", true), ("screen_name", true),
        ("User_id", false), ("user_id_", false), ("userid", false), ("session", false), ("screen_name.x", false), ("Screen Name", false),
    ])
    func reservedPropertyName(name: String, skipped: Bool) throws {
        let schema = EventSchema(name: "properties_named", version: 1, consentCategory: .analytics, properties: [])
        let sut = try HeapBatchEncoder(appID: "12343283", plan: try TrackingPlan(schemas: [schema]))
        let record = EventRecord(event: PropertiesNamed(properties: [name: .string("value")]), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let expected: [HeapEncodingError] = skipped ? [.reservedPropertyName(event: "properties_named", property: name)] : []

        let actual = sut.requests(for: [record])

        #expect(actual.skippedRecords.map(\.reason) == expected)
        #expect(actual.requests.flatMap(\.recordIDs) == (skipped ? [] : [record.id]))
    }

    @Test("A property name of 1,023 characters is sent, and one of 1,024 is left out as propertyNameTooLong, counted in UTF-16", arguments: [
        (String(repeating: "p", count: 1_023), false),
        (String(repeating: "p", count: 1_024), true),
        (String(repeating: "😀", count: 511) + "p", false),
        (String(repeating: "😀", count: 512), true),
    ])
    func propertyNameLength(name: String, skipped: Bool) throws {
        let schema = EventSchema(name: "properties_named", version: 1, consentCategory: .analytics, properties: [])
        let sut = try HeapBatchEncoder(appID: "12343283", plan: try TrackingPlan(schemas: [schema]))
        let record = EventRecord(event: PropertiesNamed(properties: [name: .string("value")]), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let expected: [HeapEncodingError] = skipped ? [.propertyNameTooLong(event: "properties_named", property: name)] : []

        let actual = sut.requests(for: [record])

        #expect(actual.skippedRecords.map(\.reason) == expected)
        #expect(actual.requests.flatMap(\.recordIDs) == (skipped ? [] : [record.id]))
    }

    @Test("A nested property's name is counted whole, its path joined by '.': c. and 1,021 characters is sent, and c. and 1,022 is left out", arguments: [(1_021, false), (1_022, true)])
    func nestedPropertyNameLength(innerLength: Int, skipped: Bool) throws {
        let schema = EventSchema(name: "properties_named", version: 1, consentCategory: .analytics, properties: [])
        let sut = try HeapBatchEncoder(appID: "12343283", plan: try TrackingPlan(schemas: [schema]))
        let inner = String(repeating: "p", count: innerLength)
        let record = EventRecord(event: PropertiesNamed(properties: ["c": .object([inner: 1])]), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let expected: [HeapEncodingError] = skipped ? [.propertyNameTooLong(event: "properties_named", property: "c." + inner)] : []

        let actual = sut.requests(for: [record])

        #expect(actual.skippedRecords.map(\.reason) == expected)
        #expect(actual.requests.flatMap(\.recordIDs) == (skipped ? [] : [record.id]))
    }

    @Test("A string value of 1,023 characters is sent, and one of 1,024 is left out as propertyValueTooLong with its length", arguments: [
        (String(repeating: "v", count: 1_023), nil),
        (String(repeating: "v", count: 1_024), 1_024),
        (String(repeating: "😀", count: 511) + "v", nil),
        (String(repeating: "😀", count: 512), 1_024),
        (String(repeating: "v", count: 5_000), 5_000),
        ("", nil),
    ] as [(String, Int?)])
    func propertyValueLength(value: String, length: Int?) throws {
        let schema = EventSchema(name: "properties_named", version: 1, consentCategory: .analytics, properties: [])
        let sut = try HeapBatchEncoder(appID: "12343283", plan: try TrackingPlan(schemas: [schema]))
        let record = EventRecord(event: PropertiesNamed(properties: ["note": .string(value)]), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let expected: [HeapEncodingError] = length.map { [.propertyValueTooLong(event: "properties_named", property: "note", length: $0)] } ?? []

        let actual = sut.requests(for: [record])

        #expect(actual.skippedRecords.map(\.reason) == expected)
        #expect(actual.requests.flatMap(\.recordIDs) == (length == nil ? [record.id] : []))
    }

    @Test("Of several faults, a reserved name is reported first, then a long name, then a long value, each the first in UTF-8 order")
    func propertyFaultOrder() throws {
        let schema = EventSchema(name: "properties_named", version: 1, consentCategory: .analytics, properties: [])
        let sut = try HeapBatchEncoder(appID: "12343283", plan: try TrackingPlan(schemas: [schema]))
        let longName = String(repeating: "a", count: 1_024)
        let longValue = String(repeating: "v", count: 1_024)
        let all = PropertiesNamed(properties: ["z": .string(longValue), "b": .string(longValue), longName: .string("x"), "user_id": .string("x"), "session_id": .string("x")])
        let names = PropertiesNamed(properties: ["z": .string(longValue), longName: .string("x"), "b" + longName: .string("x")])
        let values = PropertiesNamed(properties: ["z": .string(longValue), "b": .string(longValue + "v")])
        let batch = [all, names, values].map { EventRecord(event: $0, timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil) }
        let expected: [HeapEncodingError] = [
            .reservedPropertyName(event: "properties_named", property: "session_id"),
            .propertyNameTooLong(event: "properties_named", property: longName),
            .propertyValueTooLong(event: "properties_named", property: "b", length: 1_025),
        ]

        let actual = sut.requests(for: batch)

        #expect(actual.skippedRecords.map(\.reason) == expected)
        #expect(actual.requests.isEmpty)
    }

    @Test("A record whose values flatten to one name is left out as propertyNameCollision")
    func collision() throws {
        let schema = EventSchema(name: "properties_named", version: 1, consentCategory: .analytics, properties: [])
        let sut = try HeapBatchEncoder(appID: "12343283", plan: try TrackingPlan(schemas: [schema]))
        let record = EventRecord(event: PropertiesNamed(properties: ["cart.size": .string("2"), "cart": .object(["size": 2])]), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let expected: [HeapEncodingError] = [.propertyNameCollision(event: "properties_named", property: "cart.size")]

        let actual = sut.requests(for: [record])

        #expect(actual.skippedRecords.map(\.reason) == expected)
        #expect(actual.requests.isEmpty)
    }

    @Test("A record whose event isn't Encodable is left out as notEncodable")
    func notEncodable() throws {
        let schema = EventSchema(name: "HandWritten", version: 1, consentCategory: .analytics, properties: [EventSchema.Property(name: "plan", typeName: "String", isOptional: false)])
        let sut = try HeapBatchEncoder(appID: "12343283", plan: try TrackingPlan(schemas: [schema]))
        let record = EventRecord(event: HandWritten(plan: "pro"), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let expected: [HeapEncodingError] = [.notEncodable(name: "HandWritten")]

        let actual = sut.requests(for: [record]).skippedRecords.map(\.reason)

        #expect(actual == expected)
    }

    @Test("A record holding a NaN or infinite number is left out as unrepresentableValue", arguments: [Double.nan, .infinity, -.infinity])
    func unrepresentableValue(value: Double) throws {
        let sut = try HeapBatchEncoder(appID: "12343283", plan: try TrackingPlan(schemas: [Measured.schema]))
        let record = EventRecord(event: Measured(value: value), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let expected: [HeapEncodingError] = [.unrepresentableValue(event: "measured", property: "value")]

        let actual = sut.requests(for: [record]).skippedRecords.map(\.reason)

        #expect(actual == expected)
    }

    // -62,135,596,800 seconds is 0001-01-01T00:00:00Z and 253,402,300,800 is 10000-01-01T00:00:00Z.
    @Test("A timestamp from 0001-01-01 to before 10000-01-01 is sent, and one outside, NaN or infinite is left out as unrepresentableTimestamp", arguments: [
        (-62_135_596_800, "0001-01-01T00:00:00.000Z"),
        (253_402_300_799.999, "9999-12-31T23:59:59.999Z"),
        (0, "1970-01-01T00:00:00.000Z"),
        (-62_135_596_800.001, nil),
        (253_402_300_800, nil),
        (.nan, nil),
        (.infinity, nil),
        (-.infinity, nil),
    ] as [(Double, String?)])
    func timestampRange(seconds: Double, expectedTimestamp: String?) throws {
        let sut = try HeapBatchEncoder(appID: "12343283", plan: try TrackingPlan(schemas: [Measured.schema]))
        let record = EventRecord(event: Measured(value: 1), timestamp: Date(timeIntervalSince1970: seconds), sourceLocation: nil)
        let expectedSkipped: [HeapEncodingError] = expectedTimestamp == nil ? [.unrepresentableTimestamp] : []

        let actual = sut.requests(for: [record])

        let text = actual.requests.first.map { String(decoding: $0.body.body, as: UTF8.self) }
        #expect(actual.skippedRecords.map(\.reason) == expectedSkipped)
        if let expectedTimestamp {
            #expect(text?.contains(#""timestamp":"\#(expectedTimestamp)""#) == true)
        } else {
            #expect(actual.requests.isEmpty)
        }
    }
}
