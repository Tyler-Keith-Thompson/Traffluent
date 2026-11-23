import Events
import LifecycleTracking
import Persistence
import PropertyBased
import Testing

@Suite("Lifecycle events")
struct LifecycleEventsTests {
    @Test("An install's bytes decode to the same install, with none left over")
    func installedRoundTrip() throws {
        let expected = ApplicationInstalled(version: "1.2.0")
        var encoder = BinaryEncoder()
        expected.encode(to: &encoder)
        var decoder = BinaryDecoder(encoder.bytes)

        let actual = try ApplicationInstalled(from: &decoder)

        #expect(actual == expected)
        #expect(decoder.isAtEnd)
    }

    @Test("An update encodes its previous version, then its version, and decodes back")
    func updatedRoundTrip() throws {
        let expected = ApplicationUpdated(previousVersion: "1.1.0", version: "1.2.0")
        var reference = BinaryEncoder()
        reference.encode("1.1.0")
        reference.encode("1.2.0")
        var encoder = BinaryEncoder()
        expected.encode(to: &encoder)
        var decoder = BinaryDecoder(encoder.bytes)

        let actual = try ApplicationUpdated(from: &decoder)

        #expect(encoder.bytes == reference.bytes)
        #expect(actual == expected)
        #expect(decoder.isAtEnd)
    }

    @Test("Bytes holding a previous version but no version don't decode as an update")
    func updatedTruncated() {
        var encoder = BinaryEncoder()
        encoder.encode("1.1.0")
        var decoder = BinaryDecoder(encoder.bytes)

        #expect(throws: BinaryDecodingError.self) {
            try ApplicationUpdated(from: &decoder)
        }
    }

    @Test("An open's bytes decode to the same open, from the background or not", arguments: [false, true])
    func openedRoundTrip(fromBackground: Bool) throws {
        let expected = ApplicationOpened(fromBackground: fromBackground)
        var encoder = BinaryEncoder()
        expected.encode(to: &encoder)
        var decoder = BinaryDecoder(encoder.bytes)

        let actual = try ApplicationOpened(from: &decoder)

        #expect(actual == expected)
        #expect(decoder.isAtEnd)
    }

    @Test("Empty bytes don't decode as an open")
    func openedTruncated() {
        var decoder = BinaryDecoder([])

        #expect(throws: BinaryDecodingError.self) {
            try ApplicationOpened(from: &decoder)
        }
    }

    @Test("A move to the background and an end encode as no bytes, and decode from none")
    func propertylessRoundTrip() throws {
        var backgroundedEncoder = BinaryEncoder()
        ApplicationBackgrounded().encode(to: &backgroundedEncoder)
        var terminatedEncoder = BinaryEncoder()
        ApplicationTerminated().encode(to: &terminatedEncoder)
        var backgroundedDecoder = BinaryDecoder([])
        var terminatedDecoder = BinaryDecoder([])

        let actualBackgrounded = try ApplicationBackgrounded(from: &backgroundedDecoder)
        let actualTerminated = try ApplicationTerminated(from: &terminatedDecoder)

        #expect(backgroundedEncoder.bytes.isEmpty)
        #expect(terminatedEncoder.bytes.isEmpty)
        #expect(actualBackgrounded == ApplicationBackgrounded())
        #expect(actualTerminated == ApplicationTerminated())
    }

    @Test("Each event's schema names it, version 1 for analytics, with its properties as required values")
    func schemas() {
        let expected = [
            EventSchema(name: "ApplicationInstalled", version: 1, consentCategory: .analytics, properties: [
                EventSchema.Property(name: "version", typeName: "String", isOptional: false),
            ]),
            EventSchema(name: "ApplicationUpdated", version: 1, consentCategory: .analytics, properties: [
                EventSchema.Property(name: "previousVersion", typeName: "String", isOptional: false),
                EventSchema.Property(name: "version", typeName: "String", isOptional: false),
            ]),
            EventSchema(name: "ApplicationOpened", version: 1, consentCategory: .analytics, properties: [
                EventSchema.Property(name: "fromBackground", typeName: "Bool", isOptional: false),
            ]),
            EventSchema(name: "ApplicationBackgrounded", version: 1, consentCategory: .analytics, properties: []),
            EventSchema(name: "ApplicationTerminated", version: 1, consentCategory: .analytics, properties: []),
        ]

        let actual = [
            ApplicationInstalled.schema,
            ApplicationUpdated.schema,
            ApplicationOpened.schema,
            ApplicationBackgrounded.schema,
            ApplicationTerminated.schema,
        ]

        #expect(actual == expected)
    }

    @Test("An update encodes as its two versions and decodes back, for any two strings")
    func updatedEncodingProperty() async {
        await propertyCheck(count: 300, input: Gen.uint8().array(of: 0...24), Gen.uint8().array(of: 0...24)) { previousBytes, versionBytes in
            let previous = String(decoding: previousBytes, as: UTF8.self)
            let version = String(decoding: versionBytes, as: UTF8.self)
            let update = ApplicationUpdated(previousVersion: previous, version: version)
            var reference = BinaryEncoder()
            reference.encode(previous)
            reference.encode(version)

            var encoder = BinaryEncoder()
            update.encode(to: &encoder)
            var decoder = BinaryDecoder(encoder.bytes)
            let decoded = try? ApplicationUpdated(from: &decoder)

            #expect(encoder.bytes == reference.bytes)
            #expect(decoded == update)
            #expect(decoder.isAtEnd)
        }
    }
}
