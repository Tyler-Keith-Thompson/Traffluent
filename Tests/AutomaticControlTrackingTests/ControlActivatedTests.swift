import AutomaticControlTracking
import CBOR
import Events
import PropertyBased
import Testing

@Suite("ControlActivated")
struct ControlActivatedTests {
    @Test("A control activation's CBOR decodes to the same activation")
    func roundTrip() throws {
        let expected = ControlActivated(control: "checkout-button", kind: "UIButton")
        let bytes = try CBOREncoder().encode(expected)

        let actual = try CBORDecoder().decode(ControlActivated.self, from: bytes)

        #expect(actual == expected)
    }

    @Test("An activation of empty names round-trips too")
    func emptyRoundTrip() throws {
        let expected = ControlActivated(control: "", kind: "")
        let bytes = try CBOREncoder().encode(expected)

        let actual = try CBORDecoder().decode(ControlActivated.self, from: bytes)

        #expect(actual == expected)
    }

    @Test("A map holding a name but no kind doesn't decode: keyNotFound names kind")
    func truncated() {
        let bytes = CBOR.map([.textString("control"): .textString("checkout-button")]).encode()
        let expectedKey = "kind"

        let error = #expect(throws: DecodingError.self) {
            try CBORDecoder().decode(ControlActivated.self, from: bytes)
        }

        guard case .keyNotFound(let key, _) = error else {
            Issue.record("Expected keyNotFound, got \(String(describing: error))")
            return
        }
        #expect(key.stringValue == expectedKey)
    }

    @Test("Its schema names the event, version 1 for analytics, with the control's name and kind as required Strings")
    func schema() {
        let expected = EventSchema(
            name: "ControlActivated",
            version: 1,
            consentCategory: .analytics,
            properties: [
                EventSchema.Property(name: "control", typeName: "String", isOptional: false),
                EventSchema.Property(name: "kind", typeName: "String", isOptional: false),
            ]
        )

        let actual = ControlActivated.schema

        #expect(actual == expected)
    }

    @Test("An activation encodes as the map of its name and its kind CBOR's value model writes, and decodes back, for any two strings")
    func encodingProperty() async {
        await propertyCheck(count: 300, input: Gen.uint8().array(of: 0...24), Gen.uint8().array(of: 0...24)) { controlBytes, kindBytes in
            let control = String(decoding: controlBytes, as: UTF8.self)
            let kind = String(decoding: kindBytes, as: UTF8.self)
            let activation = ControlActivated(control: control, kind: kind)
            let reference = CBOR.map([.textString("control"): .textString(control), .textString("kind"): .textString(kind)]).encode()

            let bytes = try? CBOREncoder().encode(activation)
            let decoded = try? CBORDecoder().decode(ControlActivated.self, from: reference)

            #expect(bytes == reference)
            #expect(decoded == activation)
        }
    }
}
