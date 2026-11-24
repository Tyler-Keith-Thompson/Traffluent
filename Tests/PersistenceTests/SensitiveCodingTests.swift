import Events
import Foundation
import Persistence
import Testing

@Suite("BinaryCodable: sensitive values")
struct SensitiveCodingTests {
    // An adopter's event, declared as any app declares one: its encoding is written with the
    // public API alone.
    struct SignedUp: Event, BinaryCodable {
        var plan: String
        var email: Sensitive<String>

        init(plan: String, email: Sensitive<String>) {
            self.plan = plan
            self.email = email
        }

        func encode(to encoder: inout BinaryEncoder) {
            encoder.encodeMap { map in
                map.encode(plan, forKey: "plan")
                map.encode(email, forKey: "email")
            }
        }

        init(from decoder: inout BinaryDecoder) throws(BinaryDecodingError) {
            var map = try decoder.decodeMap()
            plan = try map.decode(forKey: "plan")
            email = try map.decode(forKey: "email")
        }
    }

    @Test("An encoder of one's own writes CBOR's undefined for a sensitive value, never the value")
    func ownEncoderWritesUndefined() {
        let expected: [UInt8] = [0xF7]
        var sut = BinaryEncoder()

        sut.encode(Sensitive("ada@example.com"))

        #expect(sut.bytes == expected)
    }

    @Test("A redacted record's event encoded with an encoder of one's own holds its other properties, and undefined for its sensitive value")
    func redactedEventNotRecovered() {
        let record = EventRecord(event: SignedUp(plan: "pro", email: Sensitive("ada@example.com")), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)
        let secret = Array("ada@example.com".utf8)
        // {"plan": "pro", "email": undefined}
        let expected: [UInt8] = [0xA2, 0x64, 0x70, 0x6C, 0x61, 0x6E, 0x63, 0x70, 0x72, 0x6F, 0x65, 0x65, 0x6D, 0x61, 0x69, 0x6C, 0xF7]
        var sut = BinaryEncoder()

        (record.event as? SignedUp)?.encode(to: &sut)

        #expect(sut.bytes == expected)
        let holdsSecret = sut.bytes.indices.contains { sut.bytes[$0...].starts(with: secret) }
        #expect(!holdsSecret)
    }

    @Test("A decoder of one's own throws invalidValue for a sensitive value, even from bytes holding one")
    func ownDecoderThrows() {
        var store = BinaryEncoder(writingSensitiveValues: true)
        store.encode(Sensitive("ada@example.com"))
        let expected = BinaryDecodingError.invalidValue
        var sut = BinaryDecoder(store.bytes)

        #expect(throws: expected) {
            let _: Sensitive<String> = try sut.decode()
        }
    }

    @Test("A store's encoder and decoder round-trip an adopter's event with a sensitive value")
    func storeRoundTrip() throws {
        let expected = "ada@example.com"
        var encoder = BinaryEncoder(writingSensitiveValues: true)

        encoder.encode(SignedUp(plan: "pro", email: Sensitive(expected)))
        var decoder = BinaryDecoder(encoder.bytes[...], readingSensitiveValues: true)
        let actual: SignedUp = try decoder.decode()

        #expect(actual.email.value == expected)
        #expect(actual.plan == "pro")
        #expect(decoder.isAtEnd)
    }
}
