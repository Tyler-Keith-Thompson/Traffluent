import EventMacros
import Foundation
import HTTPDestinations
import Instrumentation
import MatomoEncoding
import Sessions
import Synchronization
import Testing
import TrackingPlans

// Matomo's rules, from matomo-org/matomo 6.0.0 (read 2026-11-27): an event's category and action
// are trimmed and refused when empty (plugins/Events/Columns), stored in at most 4,096 characters
// (log_action.name), after line breaks and NULs are removed and `&`, `<`, `>`, `"` and `'` are
// escaped (core/Common.php); a custom dimension keeps 250 characters of its trimmed value
// (CustomDimensionsRequestProcessor); a cdt a day old or more needs token_auth, and one more than
// a day ahead is refused (core/Tracker/Request.php). The encoder leaves out a record 23 hours or
// more from when it is encoded.
@Suite("MatomoBatchEncoder: skipped records")
struct MatomoSkippedRecordTests {
    @Event(name: "checkout_started", version: 2)
    struct CheckoutStarted {
        var cartSize: Int
    }

    @Event(name: "measured")
    struct Measured {
        var value: Double
    }

    @Event(name: "weighed")
    struct Weighed {
        var weight: Sensitive<Double>
    }

    @Event(name: "noted")
    struct Noted {
        var first: String
        var second: String
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

    /// An event named by its test that isn't Encodable.
    struct NamedHandWritten: Event {
        @TaskLocal static var testName = "named_hand_written"

        static var name: String { testName }
    }

    @Test("A record whose event the plan doesn't describe is left out as unknownEvent, and the records around it are sent")
    func unknownEvent() throws {
        let sut = try MatomoBatchEncoder(siteID: 1, dimensions: [:], category: "Shop", plan: try TrackingPlan(schemas: [CheckoutStarted.schema]), now: { Date(timeIntervalSince1970: 1_795_442_607) })
        let skipped = EventRecord(event: Measured(value: 1), timestamp: Date(timeIntervalSince1970: 1_795_442_608), sourceLocation: nil)
        let batch = [
            EventRecord(id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!, event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil),
            skipped,
            EventRecord(id: UUID(uuidString: "00000000-0000-4000-8000-000000000003")!, event: CheckoutStarted(cartSize: 3), timestamp: Date(timeIntervalSince1970: 1_795_442_609), sourceLocation: nil),
        ]
        let expectedBodies = [#"{"requests":["?idsite=1&rec=1&apiv=1&_id=8000000000000001&cdt=1795442607&ca=1&e_c=Shop&e_a=checkout_started","?idsite=1&rec=1&apiv=1&_id=8000000000000003&cdt=1795442609&ca=1&e_c=Shop&e_a=checkout_started"]}"#]
        let expectedSkipped = [SkippedRecord<MatomoEncodingError>(recordID: skipped.id, eventName: "measured", schemaVersion: 1, reason: .unknownEvent(name: "measured", version: 1))]

        let actual = sut.requests(for: batch)

        let actualBodies = actual.requests.map { String(decoding: $0.body.body, as: UTF8.self) }
        #expect(actualBodies == expectedBodies)
        #expect(actual.skippedRecords == expectedSkipped)
    }

    @Test("A record whose version the plan doesn't describe is left out as unknownEvent with its version, though the plan has its name")
    func unknownVersion() throws {
        let earlier = EventSchema(name: "checkout_started", version: 1, consentCategory: .analytics, properties: [])
        let sut = try MatomoBatchEncoder(siteID: 1, dimensions: [:], category: "Shop", plan: try TrackingPlan(schemas: [earlier]), now: { Date(timeIntervalSince1970: 1_795_442_607) })
        let record = EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let expected = [SkippedRecord<MatomoEncodingError>(recordID: record.id, eventName: "checkout_started", schemaVersion: 2, reason: .unknownEvent(name: "checkout_started", version: 2))]

        let actual = sut.requests(for: [record]).skippedRecords

        #expect(actual == expected)
    }

    static let eventNames: [(String, Bool)] = [
        (" ", true), ("\n", true), ("\r\n\t\0\u{0B}", true), (String(repeating: "a", count: 4097), true), (String(repeating: "&", count: 820), true),
        (String(repeating: "\"", count: 683), true), (String(repeating: ">", count: 1025), true), (String(repeating: "😀", count: 4097), true),
        ("a", false), (" a ", false), ("a\nb", false), (String(repeating: "a", count: 4096), false), (String(repeating: "&", count: 819), false),
        (String(repeating: "\"", count: 682), false), (String(repeating: ">", count: 1024), false), (String(repeating: "😀", count: 4096), false),
        ("\t" + String(repeating: "a", count: 4096) + " ", false), (String(repeating: "a", count: 4096) + String(repeating: "\r", count: 100), false),
    ]

    @Test("An event name Matomo would empty or cut short is left out as invalidEventName, and the last that fits is sent", arguments: Self.eventNames)
    func invalidEventName(name: String, isSkipped: Bool) throws {
        try Named.$testName.withValue(name) {
            let schema = EventSchema(name: name, version: 1, consentCategory: .analytics, properties: [])
            let sut = try MatomoBatchEncoder(siteID: 1, dimensions: [:], category: "Shop", plan: try TrackingPlan(schemas: [schema]), now: { Date(timeIntervalSince1970: 1_795_442_607) })
            let record = EventRecord(event: Named(), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
            let expected: [MatomoEncodingError] = isSkipped ? [.invalidEventName(name: name)] : []
            let expectedSent: [UUID] = isSkipped ? [] : [record.id]

            let actual = sut.requests(for: [record])

            let actualSent = actual.requests.flatMap(\.recordIDs)
            #expect(actual.skippedRecords.map(\.reason) == expected)
            #expect(actualSent == expectedSent)
        }
    }

    @Test("An invalid event name is reported before an unencodable event, but after an event the plan doesn't describe")
    func nameOrder() throws {
        try NamedHandWritten.$testName.withValue(" ") {
            let named = EventSchema(name: " ", version: 1, consentCategory: .analytics, properties: [])
            let sut = try MatomoBatchEncoder(siteID: 1, dimensions: [:], category: "Shop", plan: try TrackingPlan(schemas: [named]), now: { Date(timeIntervalSince1970: 1_795_442_607) })
            let unknown = try MatomoBatchEncoder(siteID: 1, dimensions: [:], category: "Shop", plan: try TrackingPlan(schemas: []), now: { Date(timeIntervalSince1970: 1_795_442_607) })
            let record = EventRecord(event: NamedHandWritten(), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
            let expected: [MatomoEncodingError] = [.invalidEventName(name: " ")]
            let expectedUnknown: [MatomoEncodingError] = [.unknownEvent(name: " ", version: 1)]

            let actual = sut.requests(for: [record]).skippedRecords.map(\.reason)
            let actualUnknown = unknown.requests(for: [record]).skippedRecords.map(\.reason)

            #expect(actual == expected)
            #expect(actualUnknown == expectedUnknown)
        }
    }

    @Test("A record whose event isn't Encodable is left out as notEncodable")
    func notEncodable() throws {
        let schema = EventSchema(name: "HandWritten", version: 1, consentCategory: .analytics, properties: [EventSchema.Property(name: "plan", typeName: "String", isOptional: false)])
        let sut = try MatomoBatchEncoder(siteID: 1, dimensions: ["plan": 1], category: "Shop", plan: try TrackingPlan(schemas: [schema]), now: { Date(timeIntervalSince1970: 1_795_442_607) })
        let record = EventRecord(event: HandWritten(plan: "pro"), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let expected: [MatomoEncodingError] = [.notEncodable(name: "HandWritten")]

        let actual = sut.requests(for: [record])

        #expect(actual.skippedRecords.map(\.reason) == expected)
        #expect(actual.requests.isEmpty)
    }

    @Test("A record holding a NaN or an infinite number is left out as unrepresentableValue, mapped to a dimension or not", arguments: [Double.nan, .infinity, -.infinity])
    func unrepresentableValue(value: Double) throws {
        let mapped = try MatomoBatchEncoder(siteID: 1, dimensions: ["value": 1], category: "Shop", plan: try TrackingPlan(schemas: [Measured.schema]), now: { Date(timeIntervalSince1970: 1_795_442_607) })
        let unmapped = try MatomoBatchEncoder(siteID: 1, dimensions: [:], category: "Shop", plan: try TrackingPlan(schemas: [Measured.schema]), now: { Date(timeIntervalSince1970: 1_795_442_607) })
        let record = EventRecord(event: Measured(value: value), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let expected: [MatomoEncodingError] = [.unrepresentableValue(event: "measured", property: "value")]

        let actualMapped = mapped.requests(for: [record])
        let actualUnmapped = unmapped.requests(for: [record])

        #expect(actualMapped.skippedRecords.map(\.reason) == expected)
        #expect(actualUnmapped.skippedRecords.map(\.reason) == expected)
        #expect(actualMapped.requests.isEmpty)
    }

    @Test("A Sensitive value is never read, even when the record reveals it, so a NaN one leaves the record to be sent")
    func sensitiveNeverRead() throws {
        let sut = try MatomoBatchEncoder(siteID: 1, dimensions: [:], category: "Shop", plan: try TrackingPlan(schemas: [Weighed.schema]), now: { Date(timeIntervalSince1970: 1_795_442_607) })
        var record = EventRecord(event: Weighed(weight: Sensitive(.nan)), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        record.revealsSensitiveValues = true
        let expectedSent = [record.id]

        let actual = sut.requests(for: [record])

        let actualSent = actual.requests.flatMap(\.recordIDs)
        #expect(actual.skippedRecords.isEmpty)
        #expect(actualSent == expectedSent)
    }

    @Test("A record whose timestamp is NaN, infinite or past whole seconds of Int64 is left out as unrepresentableTimestamp, whatever the clock says", arguments: [
        Double.nan, .infinity, -.infinity, 9.3e18, -9.3e18,
    ])
    func unrepresentableTimestamp(seconds: Double) throws {
        let sut = try MatomoBatchEncoder(siteID: 1, dimensions: [:], category: "Shop", plan: try TrackingPlan(schemas: [CheckoutStarted.schema]), now: { Date(timeIntervalSince1970: seconds) })
        let record = EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: seconds), sourceLocation: nil)
        let expected: [MatomoEncodingError] = [.unrepresentableTimestamp]

        let actual = sut.requests(for: [record])

        #expect(actual.skippedRecords.map(\.reason) == expected)
        #expect(actual.requests.isEmpty)
    }

    @Test("A record tracked more than 23 hours before or after the batch is encoded is left out as timestampOutsideWindow, and one at 23 hours is sent", arguments: [
        (-82_800.001, true), (-86_400, true), (-1e9, true), (82_800.001, true), (86_400, true), (1e9, true),
        (-82_800, false), (-82_799.999, false), (0, false), (82_799.999, false), (82_800, false),
    ])
    func timestampOutsideWindow(offset: Double, isSkipped: Bool) throws {
        let now = Date(timeIntervalSince1970: 1_795_442_607)
        let sut = try MatomoBatchEncoder(siteID: 1, dimensions: [:], category: "Shop", plan: try TrackingPlan(schemas: [CheckoutStarted.schema]), now: { now })
        let record = EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: now.addingTimeInterval(offset), sourceLocation: nil)
        let expected: [MatomoEncodingError] = isSkipped ? [.timestampOutsideWindow] : []
        let expectedSent: [UUID] = isSkipped ? [] : [record.id]

        let actual = sut.requests(for: [record])

        let actualSent = actual.requests.flatMap(\.recordIDs)
        #expect(actual.skippedRecords.map(\.reason) == expected)
        #expect(actualSent == expectedSent)
    }

    @Test("A clock that reads NaN or infinite leaves out every record as timestampOutsideWindow, rather than leave the window to Matomo", arguments: [Double.nan, .infinity, -.infinity])
    func nonFiniteClock(now: Double) throws {
        let sut = try MatomoBatchEncoder(siteID: 1, dimensions: [:], category: "Shop", plan: try TrackingPlan(schemas: [CheckoutStarted.schema]), now: { Date(timeIntervalSince1970: now) })
        let batch = [
            EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil),
            EventRecord(event: CheckoutStarted(cartSize: 2), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil),
        ]
        let expected: [MatomoEncodingError] = [.timestampOutsideWindow, .timestampOutsideWindow]

        let actual = sut.requests(for: batch)

        #expect(actual.skippedRecords.map(\.reason) == expected)
        #expect(actual.requests.isEmpty)
    }

    @Test("The clock is read once a batch, when it is encoded", arguments: [1, 3])
    func clockReadOnce(count: Int) throws {
        let reads = Reads()
        let sut = try MatomoBatchEncoder(siteID: 1, dimensions: [:], category: "Shop", plan: try TrackingPlan(schemas: [CheckoutStarted.schema]), now: {
            reads.count.withLock { $0 += 1 }
            return Date(timeIntervalSince1970: 1_795_442_607)
        })
        let batch = (0 ..< count).map { _ in EventRecord(event: CheckoutStarted(cartSize: 1), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil) }
        let expected = 1

        _ = sut.requests(for: batch)

        let actual = reads.count.withLock { $0 }
        #expect(actual == expected)
    }

    /// How many times a clock was read.
    final class Reads: Sendable {
        let count = Mutex(0)
    }

    static let dimensionValues: [(String, Int?)] = [
        (String(repeating: "a", count: 251), 251), (String(repeating: "&", count: 51), 255), (String(repeating: "'", count: 42), 252), (String(repeating: "é", count: 251), 251),
        (String(repeating: "e\u{301}", count: 126), 252),
        (String(repeating: "a", count: 250), nil), (String(repeating: "&", count: 50), nil), (String(repeating: "'", count: 41), nil), (String(repeating: "é", count: 250), nil),
        (String(repeating: "e\u{301}", count: 125), nil),
        (" " + String(repeating: "a", count: 250) + "\t\n", nil), (String(repeating: "a", count: 250) + "\r\n\r\n", nil), ("", nil),
    ]

    @Test("A dimension's value longer than the 250 characters Matomo keeps, as it stores them, is left out as dimensionValueTooLong, and the last that fits is sent", arguments: Self.dimensionValues)
    func dimensionValueTooLong(value: String, length: Int?) throws {
        let sut = try MatomoBatchEncoder(siteID: 1, dimensions: ["first": 4], category: "Shop", plan: try TrackingPlan(schemas: [Noted.schema]), now: { Date(timeIntervalSince1970: 1_795_442_607) })
        let record = EventRecord(event: Noted(first: value, second: String(repeating: "b", count: 1000)), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let expected: [MatomoEncodingError] = length.map { [.dimensionValueTooLong(event: "noted", property: "first", dimension: 4, length: $0)] } ?? []
        let expectedSent: [UUID] = length == nil ? [record.id] : []

        let actual = sut.requests(for: [record])

        let actualSent = actual.requests.flatMap(\.recordIDs)
        #expect(actual.skippedRecords.map(\.reason) == expected)
        #expect(actualSent == expectedSent)
    }

    @Test("Of two dimensions' values too long, the one of the lower dimension is reported")
    func dimensionOrder() throws {
        let sut = try MatomoBatchEncoder(siteID: 1, dimensions: ["first": 9, "second": 2], category: "Shop", plan: try TrackingPlan(schemas: [Noted.schema]), now: { Date(timeIntervalSince1970: 1_795_442_607) })
        let record = EventRecord(event: Noted(first: String(repeating: "a", count: 300), second: String(repeating: "b", count: 260)), timestamp: Date(timeIntervalSince1970: 1_795_442_607), sourceLocation: nil)
        let expected: [MatomoEncodingError] = [.dimensionValueTooLong(event: "noted", property: "second", dimension: 2, length: 260)]

        let actual = sut.requests(for: [record])

        #expect(actual.skippedRecords.map(\.reason) == expected)
    }

    @Test("The reasons come in order: an unrepresentable timestamp before the window, and the window before a dimension's value")
    func reasonOrder() throws {
        let now = Date(timeIntervalSince1970: 1_795_442_607)
        let sut = try MatomoBatchEncoder(siteID: 1, dimensions: ["first": 1], category: "Shop", plan: try TrackingPlan(schemas: [Noted.schema]), now: { now })
        let tooLong = String(repeating: "a", count: 300)
        let batch = [
            EventRecord(event: Noted(first: tooLong, second: ""), timestamp: Date(timeIntervalSince1970: .nan), sourceLocation: nil),
            EventRecord(event: Noted(first: tooLong, second: ""), timestamp: now.addingTimeInterval(-90_000), sourceLocation: nil),
            EventRecord(event: Noted(first: tooLong, second: ""), timestamp: now, sourceLocation: nil),
        ]
        let expected: [MatomoEncodingError] = [.unrepresentableTimestamp, .timestampOutsideWindow, .dimensionValueTooLong(event: "noted", property: "first", dimension: 1, length: 300)]

        let actual = sut.requests(for: batch)

        #expect(actual.skippedRecords.map(\.reason) == expected)
    }
}
