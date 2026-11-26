// A Sensitive property of an @Event struct keeps its redaction: only a store's encoding writes its
// value and only a store's decoding reads it, as for a hand-written conformance.

import CBOR
import EventMacros
import Testing

@Suite("@Event: sensitive values")
struct EventMacroSensitiveTests {
    @Event
    struct SignedIn {
        var plan: String
        var email: Sensitive<String>
    }

    @Test("The schema names a sensitive property's type as written")
    func schema() {
        let expected = [
            EventSchema.Property(name: "plan", typeName: "String", isOptional: false),
            EventSchema.Property(name: "email", typeName: "Sensitive<String>", isOptional: false),
        ]

        let actual = SignedIn.schema.properties

        #expect(actual == expected)
    }

    @Test("An encoder of one's own writes the other properties and null for the sensitive one")
    func ownEncoderRedacts() throws {
        // {"plan": "pro", "email": null}, keys in CBOR's sorted order.
        let expected: [UInt8] = [0xA2, 0x64, 0x70, 0x6C, 0x61, 0x6E, 0x63, 0x70, 0x72, 0x6F, 0x65, 0x65, 0x6D, 0x61, 0x69, 0x6C, 0xF6]

        let actual = try CBOREncoder().encode(SignedIn(plan: "pro", email: Sensitive("ada@example.com")))

        #expect(actual == expected)
    }

    @Test("A store's encoding and decoding carry the sensitive value through")
    func storeRoundTrip() throws {
        let expectedEmail = "ada@example.com"
        let expectedPlan = "pro"

        let actual = try SensitiveCoding.$revealsValues.withValue(true) {
            let bytes = try CBOREncoder().encode(SignedIn(plan: expectedPlan, email: Sensitive(expectedEmail)))
            return try CBORDecoder().decode(SignedIn.self, from: bytes)
        }

        #expect(actual.plan == expectedPlan)
        #expect(actual.email.value == expectedEmail)
    }

    @Test("A decoder of one's own can't read the sensitive value back: dataCorrupted")
    func ownDecoderRefuses() throws {
        let bytes = try SensitiveCoding.$revealsValues.withValue(true) {
            try CBOREncoder().encode(SignedIn(plan: "pro", email: Sensitive("ada@example.com")))
        }

        let error = #expect(throws: DecodingError.self) {
            _ = try CBORDecoder().decode(SignedIn.self, from: bytes)
        }

        guard case .dataCorrupted = error else {
            Issue.record("Expected dataCorrupted, got \(String(describing: error))")
            return
        }
    }
}
