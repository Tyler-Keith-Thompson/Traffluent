// A Sensitive property of an @Event struct keeps its redaction: only a store's encoder writes its
// value and only a store's decoder reads it, as for a hand-written conformance.

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

    @Test("An encoder of one's own writes the other properties and undefined for the sensitive one")
    func ownEncoderRedacts() {
        var reference = BinaryEncoder()
        reference.encodeMap { map in
            map.encode("pro", forKey: "plan")
            map.encode(Sensitive("anything"), forKey: "email")
        }
        let expected = reference.bytes
        var sut = BinaryEncoder()

        SignedIn(plan: "pro", email: Sensitive("ada@example.com")).encode(to: &sut)

        #expect(sut.bytes == expected)
    }

    @Test("A store's encoder and decoder carry the sensitive value through")
    func storeRoundTrip() throws {
        var encoder = BinaryEncoder(writingSensitiveValues: true)
        SignedIn(plan: "pro", email: Sensitive("ada@example.com")).encode(to: &encoder)
        var decoder = BinaryDecoder(encoder.bytes[...], readingSensitiveValues: true)

        let actual = try SignedIn(from: &decoder)

        #expect(actual.plan == "pro")
        #expect(actual.email.value == "ada@example.com")
        #expect(decoder.isAtEnd)
    }

    @Test("A decoder of one's own can't read the sensitive value back")
    func ownDecoderRefuses() {
        var encoder = BinaryEncoder(writingSensitiveValues: true)
        SignedIn(plan: "pro", email: Sensitive("ada@example.com")).encode(to: &encoder)
        var decoder = BinaryDecoder(encoder.bytes)

        #expect(throws: BinaryDecodingError.invalidValue) {
            _ = try SignedIn(from: &decoder)
        }
    }
}
