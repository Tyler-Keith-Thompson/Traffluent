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

    @Test("An update encodes as a map of its previous version, then its version, and decodes back")
    func updatedRoundTrip() throws {
        let expected = ApplicationUpdated(previousVersion: "1.1.0", version: "1.2.0")
        var reference = BinaryEncoder()
        reference.encodeMap { map in
            map.encode("1.1.0", forKey: "previousVersion")
            map.encode("1.2.0", forKey: "version")
        }
        var encoder = BinaryEncoder()
        expected.encode(to: &encoder)
        var decoder = BinaryDecoder(encoder.bytes)

        let actual = try ApplicationUpdated(from: &decoder)

        #expect(encoder.bytes == reference.bytes)
        #expect(actual == expected)
        #expect(decoder.isAtEnd)
    }

    @Test("A map holding a previous version but no version doesn't decode as an update")
    func updatedTruncated() {
        var encoder = BinaryEncoder()
        encoder.encodeMap { map in
            map.encode("1.1.0", forKey: "previousVersion")
        }
        var decoder = BinaryDecoder(encoder.bytes)

        #expect(throws: BinaryDecodingError.keyNotFound) {
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

    @Test("A move to the background and an end encode as an empty map, and decode from one")
    func propertylessRoundTrip() throws {
        let expectedBytes: [UInt8] = [0xA0]
        var backgroundedEncoder = BinaryEncoder()
        ApplicationBackgrounded().encode(to: &backgroundedEncoder)
        var terminatedEncoder = BinaryEncoder()
        ApplicationTerminated().encode(to: &terminatedEncoder)
        var backgroundedDecoder = BinaryDecoder(expectedBytes)
        var terminatedDecoder = BinaryDecoder(expectedBytes)

        let actualBackgrounded = try ApplicationBackgrounded(from: &backgroundedDecoder)
        let actualTerminated = try ApplicationTerminated(from: &terminatedDecoder)

        #expect(backgroundedEncoder.bytes == expectedBytes)
        #expect(terminatedEncoder.bytes == expectedBytes)
        #expect(backgroundedDecoder.isAtEnd)
        #expect(terminatedDecoder.isAtEnd)
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

    @Test("An update encodes as a map of its two versions and decodes back, for any two strings")
    func updatedEncodingProperty() async {
        await propertyCheck(count: 300, input: Gen.uint8().array(of: 0...24), Gen.uint8().array(of: 0...24)) { previousBytes, versionBytes in
            let previous = String(decoding: previousBytes, as: UTF8.self)
            let version = String(decoding: versionBytes, as: UTF8.self)
            let update = ApplicationUpdated(previousVersion: previous, version: version)
            var reference = BinaryEncoder()
            reference.encodeMap { map in
                map.encode(previous, forKey: "previousVersion")
                map.encode(version, forKey: "version")
            }

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
