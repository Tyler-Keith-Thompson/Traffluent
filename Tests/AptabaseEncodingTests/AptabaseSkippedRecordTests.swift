import AptabaseEncoding
import EventMacros
import Foundation
import HTTPDestinations
import Testing
import TrackingPlans

// Aptabase's rules are its server's (github.com/aptabase/aptabase at 89d36185,
// src/Features/Ingestion/EventBody.cs and EventsController.cs, read 2026-11-27): an event name
// [Required, StringLength(60)]; a property key not IsNullOrWhiteSpace and at most 40 characters; a
// string value cut past 180; a number read as a .NET decimal; a time readable as a DateTime, and
// no more than a day old. .NET counts a string's length in UTF-16 code units, so an emoji outside
// the Basic Multilingual Plane counts two.
// Private: its events share their names with other events of this test target, and @Event
// leaves a private type's events out of the link check of names (DefiningEvents, Limits).
@Suite("AptabaseBatchEncoder: skipped records")
private struct AptabaseSkippedRecordTests {
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
            case number(Double)
            case integer(Int64)
            case object([String: Int])

            func encode(to encoder: any Encoder) throws {
                var container = encoder.singleValueContainer()
                switch self {
                case .string(let value): try container.encode(value)
                case .number(let value): try container.encode(value)
                case .integer(let value): try container.encode(value)
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
        let tracked = Date(timeIntervalSince1970: 1_795_442_607)
        let sut = AptabaseBatchEncoder(isDebug: false, plan: try TrackingPlan(schemas: [CheckoutStarted.schema]), now: { tracked })
        let skipped = EventRecord(event: Measured(value: 1), timestamp: tracked, sourceLocation: nil)
        let batch = [
            EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: tracked, sourceLocation: nil),
            skipped,
            EventRecord(event: CheckoutStarted(cartSize: 3), timestamp: tracked, sourceLocation: nil),
        ]
        let expectedBody = try #require(sut.requests(for: [batch[0], batch[2]]).requests.first).body
        let expectedSkipped = [SkippedRecord<AptabaseEncodingError>(recordID: skipped.id, eventName: "measured", schemaVersion: 1, reason: .unknownEvent(name: "measured", version: 1))]

        let actual = sut.requests(for: batch)

        #expect(actual.requests.map(\.body) == [expectedBody])
        #expect(actual.skippedRecords == expectedSkipped)
    }

    @Test("A record whose version the plan doesn't describe is left out as unknownEvent with its version, though the plan has its name")
    func unknownVersion() throws {
        let tracked = Date(timeIntervalSince1970: 1_795_442_607)
        let earlier = EventSchema(name: "checkout_started", version: 1, consentCategory: .analytics, properties: [])
        let sut = AptabaseBatchEncoder(isDebug: false, plan: try TrackingPlan(schemas: [earlier]), now: { tracked })
        let record = EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: tracked, sourceLocation: nil)
        let expected = [SkippedRecord<AptabaseEncodingError>(recordID: record.id, eventName: "checkout_started", schemaVersion: 2, reason: .unknownEvent(name: "checkout_started", version: 2))]

        let actual = sut.requests(for: [record]).skippedRecords

        #expect(actual == expected)
    }

    @Test("An event name of 60 characters is sent, and one of 61 or only whitespace is left out as invalidEventName, counted in UTF-16", arguments: [
        (String(repeating: "e", count: 60), false),
        (String(repeating: "e", count: 61), true),
        (String(repeating: "😀", count: 30), false),
        (String(repeating: "😀", count: 30) + "e", true),
        (String(repeating: "é", count: 60), false),
        ("e", false),
        (" e ", false),
        (" ", true),
        ("\t\n", true),
        ("\u{3000}\u{00A0}", true),
        ("\u{200B}", false),
    ])
    func eventName(name: String, skipped: Bool) throws {
        let tracked = Date(timeIntervalSince1970: 1_795_442_607)
        try Named.$testName.withValue(name) {
            let schema = EventSchema(name: name, version: 1, consentCategory: .analytics, properties: [])
            let sut = AptabaseBatchEncoder(isDebug: false, plan: try TrackingPlan(schemas: [schema]), now: { tracked })
            let record = EventRecord(event: Named(), timestamp: tracked, sourceLocation: nil)
            let expected: [AptabaseEncodingError] = skipped ? [.invalidEventName(name: name)] : []

            let actual = sut.requests(for: [record])

            #expect(actual.skippedRecords.map(\.reason) == expected)
            #expect(actual.requests.flatMap(\.recordIDs) == (skipped ? [] : [record.id]))
        }
    }

    @Test("An event name too long is reported before the event's other faults, but after an event the plan doesn't describe")
    func eventNameOrder() throws {
        let tracked = Date(timeIntervalSince1970: 1_795_442_607)
        let name = String(repeating: "e", count: 61)
        try Named.$testName.withValue(name) {
            let schema = EventSchema(name: name, version: 1, consentCategory: .analytics, properties: [])
            let sut = AptabaseBatchEncoder(isDebug: false, plan: try TrackingPlan(schemas: [schema]), now: { tracked })
            let other = AptabaseBatchEncoder(isDebug: false, plan: try TrackingPlan(schemas: []), now: { tracked })
            let record = EventRecord(event: NamedHandWritten(), timestamp: tracked, sourceLocation: nil)
            let expected: [AptabaseEncodingError] = [.invalidEventName(name: name)]
            let expectedUnknown: [AptabaseEncodingError] = [.unknownEvent(name: name, version: 1)]

            let actual = sut.requests(for: [record]).skippedRecords.map(\.reason)
            let actualUnknown = other.requests(for: [record]).skippedRecords.map(\.reason)

            #expect(actual == expected)
            #expect(actualUnknown == expectedUnknown)
        }
    }

    @Test("A property name of 40 characters is sent, and one of 41 is left out as propertyNameTooLong, counted in UTF-16", arguments: [
        (String(repeating: "p", count: 40), false),
        (String(repeating: "p", count: 41), true),
        (String(repeating: "😀", count: 20), false),
        (String(repeating: "😀", count: 20) + "p", true),
    ])
    func propertyNameLength(name: String, skipped: Bool) throws {
        let tracked = Date(timeIntervalSince1970: 1_795_442_607)
        let schema = EventSchema(name: "properties_named", version: 1, consentCategory: .analytics, properties: [])
        let sut = AptabaseBatchEncoder(isDebug: false, plan: try TrackingPlan(schemas: [schema]), now: { tracked })
        let record = EventRecord(event: PropertiesNamed(properties: [name: .string("value")]), timestamp: tracked, sourceLocation: nil)
        let expected: [AptabaseEncodingError] = skipped ? [.propertyNameTooLong(event: "properties_named", property: name)] : []

        let actual = sut.requests(for: [record])

        #expect(actual.skippedRecords.map(\.reason) == expected)
        #expect(actual.requests.flatMap(\.recordIDs) == (skipped ? [] : [record.id]))
    }

    @Test("A nested property's name is counted whole, its path joined by '.': c. and 38 characters is sent, and c. and 39 is left out", arguments: [(38, false), (39, true)])
    func nestedPropertyNameLength(innerLength: Int, skipped: Bool) throws {
        let tracked = Date(timeIntervalSince1970: 1_795_442_607)
        let schema = EventSchema(name: "properties_named", version: 1, consentCategory: .analytics, properties: [])
        let sut = AptabaseBatchEncoder(isDebug: false, plan: try TrackingPlan(schemas: [schema]), now: { tracked })
        let inner = String(repeating: "p", count: innerLength)
        let record = EventRecord(event: PropertiesNamed(properties: ["c": .object([inner: 1])]), timestamp: tracked, sourceLocation: nil)
        let expected: [AptabaseEncodingError] = skipped ? [.propertyNameTooLong(event: "properties_named", property: "c." + inner)] : []

        let actual = sut.requests(for: [record])

        #expect(actual.skippedRecords.map(\.reason) == expected)
        #expect(actual.requests.flatMap(\.recordIDs) == (skipped ? [] : [record.id]))
    }

    @Test("A property name that is empty or only whitespace is left out as emptyPropertyName, and one with another character is sent", arguments: [
        ("", true), (" ", true), ("\t", true), ("\u{2028}", true), ("\u{3000}", true), ("\u{85}", true),
        (" a", false), ("\u{200B}", false), ("_", false),
    ])
    func emptyPropertyName(name: String, skipped: Bool) throws {
        let tracked = Date(timeIntervalSince1970: 1_795_442_607)
        let schema = EventSchema(name: "properties_named", version: 1, consentCategory: .analytics, properties: [])
        let sut = AptabaseBatchEncoder(isDebug: false, plan: try TrackingPlan(schemas: [schema]), now: { tracked })
        let record = EventRecord(event: PropertiesNamed(properties: [name: .string("value")]), timestamp: tracked, sourceLocation: nil)
        let expected: [AptabaseEncodingError] = skipped ? [.emptyPropertyName(event: "properties_named", property: name)] : []

        let actual = sut.requests(for: [record])

        #expect(actual.skippedRecords.map(\.reason) == expected)
        #expect(actual.requests.flatMap(\.recordIDs) == (skipped ? [] : [record.id]))
    }

    @Test("A string value of 180 characters is sent, and one of 181 is left out as propertyValueTooLong with its length", arguments: [
        (String(repeating: "v", count: 180), nil),
        (String(repeating: "v", count: 181), 181),
        (String(repeating: "😀", count: 90), nil),
        (String(repeating: "😀", count: 90) + "v", 181),
        (String(repeating: "v", count: 5_000), 5_000),
        ("", nil),
    ] as [(String, Int?)])
    func propertyValueLength(value: String, length: Int?) throws {
        let tracked = Date(timeIntervalSince1970: 1_795_442_607)
        let schema = EventSchema(name: "properties_named", version: 1, consentCategory: .analytics, properties: [])
        let sut = AptabaseBatchEncoder(isDebug: false, plan: try TrackingPlan(schemas: [schema]), now: { tracked })
        let record = EventRecord(event: PropertiesNamed(properties: ["note": .string(value)]), timestamp: tracked, sourceLocation: nil)
        let expected: [AptabaseEncodingError] = length.map { [.propertyValueTooLong(event: "properties_named", property: "note", length: $0)] } ?? []

        let actual = sut.requests(for: [record])

        #expect(actual.skippedRecords.map(\.reason) == expected)
        #expect(actual.requests.flatMap(\.recordIDs) == (length == nil ? [record.id] : []))
    }

    // 2⁹⁶ is 79,228,162,514,264,337,593,543,950,336, one past a .NET decimal's largest value; the
    // Double just below it is an integer inside a decimal's range.
    @Test("A number of magnitude below 2⁹⁶ is sent, and one of 2⁹⁶ or more is left out as numberOutOfRange", arguments: [
        (79_228_162_514_264_337_593_543_950_336.0.nextDown, false),
        (-(79_228_162_514_264_337_593_543_950_336.0.nextDown), false),
        (79_228_162_514_264_337_593_543_950_336.0, true),
        (-79_228_162_514_264_337_593_543_950_336.0, true),
        (1e300, true),
        (-Double.greatestFiniteMagnitude, true),
        (0.5, false),
        (1e-300, false),
        (0, false),
    ])
    func numberRange(value: Double, skipped: Bool) throws {
        let tracked = Date(timeIntervalSince1970: 1_795_442_607)
        let schema = EventSchema(name: "properties_named", version: 1, consentCategory: .analytics, properties: [])
        let sut = AptabaseBatchEncoder(isDebug: false, plan: try TrackingPlan(schemas: [schema]), now: { tracked })
        let record = EventRecord(event: PropertiesNamed(properties: ["amount": .number(value)]), timestamp: tracked, sourceLocation: nil)
        let expected: [AptabaseEncodingError] = skipped ? [.numberOutOfRange(event: "properties_named", property: "amount")] : []

        let actual = sut.requests(for: [record])

        #expect(actual.skippedRecords.map(\.reason) == expected)
        #expect(actual.requests.flatMap(\.recordIDs) == (skipped ? [] : [record.id]))
    }

    @Test("Every integer is sent, Int64's least and greatest included, as a decimal holds them", arguments: [Int64.min, .max, 0])
    func integerRange(value: Int64) throws {
        let tracked = Date(timeIntervalSince1970: 1_795_442_607)
        let schema = EventSchema(name: "properties_named", version: 1, consentCategory: .analytics, properties: [])
        let sut = AptabaseBatchEncoder(isDebug: false, plan: try TrackingPlan(schemas: [schema]), now: { tracked })
        let record = EventRecord(event: PropertiesNamed(properties: ["count": .integer(value)]), timestamp: tracked, sourceLocation: nil)
        let expected = #""props":{"count":\#(value)}"#

        let actual = sut.requests(for: [record])

        #expect(actual.skippedRecords.isEmpty)
        #expect(actual.requests.first.map { String(decoding: $0.body.body, as: UTF8.self).contains(expected) } == true)
    }

    @Test("Of several faults, an empty name is reported first, then a long name, then a long value or a number out of range, each the first in UTF-8 order")
    func propertyFaultOrder() throws {
        let tracked = Date(timeIntervalSince1970: 1_795_442_607)
        let schema = EventSchema(name: "properties_named", version: 1, consentCategory: .analytics, properties: [])
        let sut = AptabaseBatchEncoder(isDebug: false, plan: try TrackingPlan(schemas: [schema]), now: { tracked })
        let longName = String(repeating: "a", count: 41)
        let longValue = String(repeating: "v", count: 181)
        let all = PropertiesNamed(properties: ["z": .string(longValue), "b": .number(1e300), longName: .string("x"), " ": .string("x")])
        let names = PropertiesNamed(properties: ["z": .string(longValue), "b" + longName: .string("x"), longName: .string("x")])
        let values = PropertiesNamed(properties: ["z": .string(longValue), "c": .number(1e300), "b": .string(longValue + "v")])
        let numbers = PropertiesNamed(properties: ["z": .string(longValue), "b": .number(-1e300)])
        let batch = [all, names, values, numbers].map { EventRecord(event: $0, timestamp: tracked, sourceLocation: nil) }
        let expected: [AptabaseEncodingError] = [
            .emptyPropertyName(event: "properties_named", property: " "),
            .propertyNameTooLong(event: "properties_named", property: longName),
            .propertyValueTooLong(event: "properties_named", property: "b", length: 182),
            .numberOutOfRange(event: "properties_named", property: "b"),
        ]

        let actual = sut.requests(for: batch)

        #expect(actual.skippedRecords.map(\.reason) == expected)
        #expect(actual.requests.isEmpty)
    }

    @Test("A record whose values flatten to one name is left out as propertyNameCollision")
    func collision() throws {
        let tracked = Date(timeIntervalSince1970: 1_795_442_607)
        let schema = EventSchema(name: "properties_named", version: 1, consentCategory: .analytics, properties: [])
        let sut = AptabaseBatchEncoder(isDebug: false, plan: try TrackingPlan(schemas: [schema]), now: { tracked })
        let record = EventRecord(event: PropertiesNamed(properties: ["cart.size": .string("2"), "cart": .object(["size": 2])]), timestamp: tracked, sourceLocation: nil)
        let expected: [AptabaseEncodingError] = [.propertyNameCollision(event: "properties_named", property: "cart.size")]

        let actual = sut.requests(for: [record])

        #expect(actual.skippedRecords.map(\.reason) == expected)
        #expect(actual.requests.isEmpty)
    }

    @Test("A record whose event isn't Encodable is left out as notEncodable")
    func notEncodable() throws {
        let tracked = Date(timeIntervalSince1970: 1_795_442_607)
        let schema = EventSchema(name: "HandWritten", version: 1, consentCategory: .analytics, properties: [EventSchema.Property(name: "plan", typeName: "String", isOptional: false)])
        let sut = AptabaseBatchEncoder(isDebug: false, plan: try TrackingPlan(schemas: [schema]), now: { tracked })
        let record = EventRecord(event: HandWritten(plan: "pro"), timestamp: tracked, sourceLocation: nil)
        let expected: [AptabaseEncodingError] = [.notEncodable(name: "HandWritten")]

        let actual = sut.requests(for: [record]).skippedRecords.map(\.reason)

        #expect(actual == expected)
    }

    @Test("A record holding a NaN or infinite number is left out as unrepresentableValue", arguments: [Double.nan, .infinity, -.infinity])
    func unrepresentableValue(value: Double) throws {
        let tracked = Date(timeIntervalSince1970: 1_795_442_607)
        let sut = AptabaseBatchEncoder(isDebug: false, plan: try TrackingPlan(schemas: [Measured.schema]), now: { tracked })
        let record = EventRecord(event: Measured(value: value), timestamp: tracked, sourceLocation: nil)
        let expected: [AptabaseEncodingError] = [.unrepresentableValue(event: "measured", property: "value")]

        let actual = sut.requests(for: [record]).skippedRecords.map(\.reason)

        #expect(actual == expected)
    }

    // -62,135,596,800 seconds is 0001-01-01T00:00:00Z and 253,402,300,800 is 10000-01-01T00:00:00Z.
    // The encoder's clock reads the record's own time where it is finite, so the 23 hours don't
    // decide.
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
        let now = Date(timeIntervalSince1970: seconds.isFinite ? seconds : 0)
        let sut = AptabaseBatchEncoder(isDebug: false, plan: try TrackingPlan(schemas: [Measured.schema]), now: { now })
        let record = EventRecord(event: Measured(value: 1), timestamp: Date(timeIntervalSince1970: seconds), sourceLocation: nil)
        let expectedSkipped: [AptabaseEncodingError] = expectedTimestamp == nil ? [.unrepresentableTimestamp] : []

        let actual = sut.requests(for: [record])

        let text = actual.requests.first.map { String(decoding: $0.body.body, as: UTF8.self) }
        #expect(actual.skippedRecords.map(\.reason) == expectedSkipped)
        if let expectedTimestamp {
            #expect(text?.contains(#""timestamp":"\#(expectedTimestamp)""#) == true)
        } else {
            #expect(actual.requests.isEmpty)
        }
    }

    // Aptabase drops an event older than DateTime.UtcNow.AddDays(-1) while answering 200, and
    // stores one from the future at the time it arrives (EventBody.Timestamp's setter).
    @Test("A record tracked up to 23 hours before the batch is encoded, or at any time after, is sent; one a millisecond older is left out as timestampOutsideWindow", arguments: [
        (-82_800, false), (-82_800.001, true), (-86_400, true), (-1e9, true), (0, false), (3_600, false), (31_536_000, false),
    ])
    func window(offset: TimeInterval, skipped: Bool) throws {
        let now = Date(timeIntervalSince1970: 1_795_442_607)
        let sut = AptabaseBatchEncoder(isDebug: false, plan: try TrackingPlan(schemas: [Measured.schema]), now: { now })
        let record = EventRecord(event: Measured(value: 1), timestamp: now.addingTimeInterval(offset), sourceLocation: nil)
        let expected: [AptabaseEncodingError] = skipped ? [.timestampOutsideWindow] : []

        let actual = sut.requests(for: [record])

        #expect(actual.skippedRecords.map(\.reason) == expected)
        #expect(actual.requests.flatMap(\.recordIDs) == (skipped ? [] : [record.id]))
    }

    @Test("Under a clock that reads NaN or infinite, every record is left out as timestampOutsideWindow", arguments: [Double.nan, .infinity, -.infinity])
    func nonFiniteClock(seconds: Double) throws {
        let now = Date(timeIntervalSince1970: seconds)
        let sut = AptabaseBatchEncoder(isDebug: false, plan: try TrackingPlan(schemas: [Measured.schema]), now: { now })
        let batch = (0 ..< 3).map { EventRecord(event: Measured(value: Double($0)), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil) }
        let expected: [AptabaseEncodingError] = Array(repeating: .timestampOutsideWindow, count: 3)

        let actual = sut.requests(for: batch)

        #expect(actual.skippedRecords.map(\.reason) == expected)
        #expect(actual.requests.isEmpty)
    }
}
