import CBOR
import Events
import Foundation
import Persistence
import Testing

@Suite("Codable: sensitive values")
struct SensitiveCodingTests {
    // An adopter's event, declared as any app declares one: its coding is Swift's own.
    struct SignedUp: Event, Codable {
        var plan: String
        var email: Sensitive<String>
    }

    @Test("An encoder of one's own writes null for a sensitive value, never the value: CBOR's and JSON's")
    func ownEncoderWritesNull() throws {
        let expectedCBOR: [UInt8] = [0xF6]
        let expectedJSON = "null"

        let cbor = try CBOREncoder().encode(Sensitive("ada@example.com"))
        let json = String(decoding: try JSONEncoder().encode(Sensitive("ada@example.com")), as: UTF8.self)

        #expect(cbor == expectedCBOR)
        #expect(json == expectedJSON)
    }

    @Test("A redacted record's event encoded with an encoder of one's own holds its other properties, and null for its sensitive value")
    func redactedEventNotRecovered() throws {
        let record = EventRecord(event: SignedUp(plan: "pro", email: Sensitive("ada@example.com")), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)
        let secret = Array("ada@example.com".utf8)
        // {"plan": "pro", "email": null}, keys in CBOR's sorted order.
        let expected: [UInt8] = [0xA2, 0x64, 0x70, 0x6C, 0x61, 0x6E, 0x63, 0x70, 0x72, 0x6F, 0x65, 0x65, 0x6D, 0x61, 0x69, 0x6C, 0xF6]
        let event = try #require(record.event as? SignedUp)

        let actual = try CBOREncoder().encode(event)

        #expect(actual == expected)
        let holdsSecret = actual.indices.contains { actual[$0...].starts(with: secret) }
        #expect(!holdsSecret)
    }

    @Test("A decoder of one's own throws dataCorrupted for a sensitive value, even from bytes holding one")
    func ownDecoderThrows() throws {
        let bytes = try SensitiveCoding.$revealsValues.withValue(true) {
            try CBOREncoder().encode(Sensitive("ada@example.com"))
        }

        let error = #expect(throws: DecodingError.self) {
            _ = try CBORDecoder().decode(Sensitive<String>.self, from: bytes)
        }

        guard case .dataCorrupted = error else {
            Issue.record("Expected dataCorrupted, got \(String(describing: error))")
            return
        }
    }

    @Test("A store's encoding and decoding round-trip an adopter's event with a sensitive value")
    func storeRoundTrip() throws {
        let expected = "ada@example.com"
        let expectedPlan = "pro"

        let actual = try SensitiveCoding.$revealsValues.withValue(true) {
            let bytes = try CBOREncoder().encode(SignedUp(plan: expectedPlan, email: Sensitive(expected)))
            return try CBORDecoder().decode(SignedUp.self, from: bytes)
        }

        #expect(actual.email.value == expected)
        #expect(actual.plan == expectedPlan)
    }
}
