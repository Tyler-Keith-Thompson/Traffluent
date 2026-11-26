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

    @Test("An event that isn't BinaryCodable throws notBinaryCodable")
    func notBinaryCodable() {
        let record = EventRecord(event: HandWritten(plan: "pro"), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)
        let expected = PropertyReadingError.notBinaryCodable(name: "HandWritten")

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
}
