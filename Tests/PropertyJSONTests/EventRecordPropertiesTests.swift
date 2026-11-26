import EventMacros
import Events
import Foundation
import Persistence
import PropertyJSON
import Testing
import TrackingPlans

// The reader's value-by-value cases run through CollectorEncodingTests, whose collector format
// writes properties exactly as read here; these pin what the module itself decides.
@Suite("EventRecord.properties(types:writingSensitiveValues:)")
struct EventRecordPropertiesTests {
    @Event(name: "signed_up")
    struct SignedUp {
        var plan: String
        var email: Sensitive<String>
        var aliases: [Sensitive<String>]
        var referrer: String?
        var trialEndsAt: Date
    }

    @Event(name: "measured")
    struct Measured {
        var value: Double
    }

    struct HandWritten: Event {
        var plan: String
    }

    // A type of the app's own, which the plan can't map: its Date is written by the CBOR package,
    // as tag 1's seconds since 1970, and its optional Sensitive value redacted as null.
    struct Shipment: Codable {
        var at: Date
        var tracking: Sensitive<String>?
    }

    @Event(name: "shipped")
    struct Shipped {
        var shipment: Shipment
        var note: Sensitive<String>?
    }

    // An optional of a type the plan's grammar can't parse.
    @Event(name: "tallied")
    struct Tallied {
        var counts: [String: Int]?
    }

    // An event whose own conformance throws.
    struct Refusing: Event, Encodable {
        struct Refused: Error {}

        func encode(to encoder: any Encoder) throws {
            throw Refused()
        }
    }

    @Test("A hand-worked event reads as JSON through its schema's types, its Sensitive values written when asked")
    func handWorked() throws {
        let record = EventRecord(
            event: SignedUp(plan: "pro", email: Sensitive("ada@example.com"), aliases: [Sensitive("ada")], referrer: nil, trialEndsAt: Date(timeIntervalSince1970: 0.125)),
            timestamp: Date(timeIntervalSince1970: 0),
            sourceLocation: nil
        )
        let expected: [String: JSON] = [
            "plan": .string("pro"),
            "email": .string("ada@example.com"),
            "aliases": .array([.string("ada")]),
            "referrer": .null,
            "trialEndsAt": .string("1970-01-01T00:00:00.125Z"),
        ]

        let actual = try record.properties(types: SignedUp.schema.propertyTypes, writingSensitiveValues: true)

        #expect(actual == expected)
    }

    @Test("Without writing Sensitive values, a Sensitive property is left out and a Sensitive element is null")
    func sensitiveLeftOut() throws {
        var record = EventRecord(
            event: SignedUp(plan: "pro", email: Sensitive("ada@example.com"), aliases: [Sensitive("ada")], referrer: "ad", trialEndsAt: Date(timeIntervalSince1970: 0)),
            timestamp: Date(timeIntervalSince1970: 0),
            sourceLocation: nil
        )
        // Revealed, so only the parameter keeps the values out.
        record.revealsSensitiveValues = true
        let expected: [String: JSON] = [
            "plan": .string("pro"),
            "aliases": .array([.null]),
            "referrer": .string("ad"),
            "trialEndsAt": .string("1970-01-01T00:00:00.000Z"),
        ]

        let actual = try record.properties(types: SignedUp.schema.propertyTypes, writingSensitiveValues: false)

        #expect(actual == expected)
    }

    @Test("propertyTypes marks an optional property's type optional")
    func optionalTypes() {
        let expected: WrittenType? = WrittenType(parsing: "String").map(WrittenType.optional)

        let actual = SignedUp.schema.propertyTypes["referrer"] ?? nil

        #expect(actual == expected)
    }

    @Test("An optional property of a type the plan can't parse is null when nil, and its value as its encoding holds it otherwise")
    func unparsedOptional() throws {
        let empty = EventRecord(event: Tallied(counts: nil), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)
        let full = EventRecord(event: Tallied(counts: ["a": 1]), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)
        let expectedEmpty: [String: JSON] = ["counts": .null]
        let expectedFull: [String: JSON] = ["counts": .object(["a": .integer(1)])]

        let actualEmpty = try empty.properties(types: Tallied.schema.propertyTypes, writingSensitiveValues: false)
        let actualFull = try full.properties(types: Tallied.schema.propertyTypes, writingSensitiveValues: false)

        #expect(actualEmpty == expectedEmpty)
        #expect(actualFull == expectedFull)
    }

    @Test("An event that isn't Encodable throws notEncodable")
    func notEncodable() {
        let record = EventRecord(event: HandWritten(plan: "pro"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)
        let expected = PropertyReadingError.notEncodable(name: "HandWritten")

        #expect(throws: expected) {
            try record.properties(types: [:], writingSensitiveValues: true)
        }
    }

    @Test("A NaN throws unrepresentableValue naming the property")
    func unrepresentable() {
        let record = EventRecord(event: Measured(value: .nan), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)
        let expected = PropertyReadingError.unrepresentableValue(event: "measured", property: "value")

        #expect(throws: expected) {
            try record.properties(types: Measured.schema.propertyTypes, writingSensitiveValues: true)
        }
    }

    @Test("A Date inside a type the plan can't map reads as its timestamp, and a redacted Sensitive value there as null")
    func nestedDate() throws {
        let record = EventRecord(
            event: Shipped(shipment: Shipment(at: Date(timeIntervalSince1970: 1.5), tracking: Sensitive("1Z")), note: Sensitive("leave at door")),
            timestamp: Date(timeIntervalSince1970: 0),
            sourceLocation: nil
        )
        let expected: [String: JSON] = [
            "shipment": .object(["at": .string("1970-01-01T00:00:01.500Z"), "tracking": .null]),
        ]

        let actual = try record.properties(types: Shipped.schema.propertyTypes, writingSensitiveValues: false)

        #expect(actual == expected)
    }

    @Test("An optional Sensitive property holding a value is left out without writing Sensitive values, and written with them")
    func optionalSensitive() throws {
        let record = EventRecord(
            event: Shipped(shipment: Shipment(at: Date(timeIntervalSince1970: 0), tracking: nil), note: Sensitive("leave at door")),
            timestamp: Date(timeIntervalSince1970: 0),
            sourceLocation: nil
        )
        let expectedRedacted: JSON? = nil
        let expectedRevealed: JSON? = .string("leave at door")

        let redacted = try record.properties(types: Shipped.schema.propertyTypes, writingSensitiveValues: false)
        let revealed = try record.properties(types: Shipped.schema.propertyTypes, writingSensitiveValues: true)

        #expect(redacted["note"] == expectedRedacted)
        #expect(revealed["note"] == expectedRevealed)
    }

    @Test("An event whose encode(to:) throws throws unrepresentableValue naming the event, with no property")
    func encodingThrows() {
        let record = EventRecord(event: Refusing(), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)
        let expected = PropertyReadingError.unrepresentableValue(event: "Refusing", property: "")

        #expect(throws: expected) {
            try record.properties(types: [:], writingSensitiveValues: true)
        }
    }
}
