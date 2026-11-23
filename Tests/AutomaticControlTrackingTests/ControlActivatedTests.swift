import AutomaticControlTracking
import Events
import Persistence
import PropertyBased
import Testing

@Suite("ControlActivated")
struct ControlActivatedTests {
    @Test("A control activation's bytes decode to the same activation, with none left over")
    func roundTrip() throws {
        let expected = ControlActivated(control: "checkout-button", kind: "UIButton")
        var encoder = BinaryEncoder()
        expected.encode(to: &encoder)
        var decoder = BinaryDecoder(encoder.bytes)

        let actual = try ControlActivated(from: &decoder)

        #expect(actual == expected)
        #expect(decoder.isAtEnd)
    }

    @Test("An activation of empty names round-trips too")
    func emptyRoundTrip() throws {
        let expected = ControlActivated(control: "", kind: "")
        var encoder = BinaryEncoder()
        expected.encode(to: &encoder)
        var decoder = BinaryDecoder(encoder.bytes)

        let actual = try ControlActivated(from: &decoder)

        #expect(actual == expected)
        #expect(decoder.isAtEnd)
    }

    @Test("Bytes holding a name but no kind don't decode")
    func truncated() {
        var encoder = BinaryEncoder()
        encoder.encode("checkout-button")
        var decoder = BinaryDecoder(encoder.bytes)

        #expect(throws: BinaryDecodingError.self) {
            try ControlActivated(from: &decoder)
        }
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

    @Test("An activation encodes as its name then its kind, and decodes back, for any two strings")
    func encodingProperty() async {
        await propertyCheck(count: 300, input: Gen.uint8().array(of: 0...24), Gen.uint8().array(of: 0...24)) { controlBytes, kindBytes in
            let control = String(decoding: controlBytes, as: UTF8.self)
            let kind = String(decoding: kindBytes, as: UTF8.self)
            let activation = ControlActivated(control: control, kind: kind)
            var reference = BinaryEncoder()
            reference.encode(control)
            reference.encode(kind)

            var encoder = BinaryEncoder()
            activation.encode(to: &encoder)
            var decoder = BinaryDecoder(encoder.bytes)
            let decoded = try? ControlActivated(from: &decoder)

            #expect(encoder.bytes == reference.bytes)
            #expect(decoded == activation)
            #expect(decoder.isAtEnd)
        }
    }
}
