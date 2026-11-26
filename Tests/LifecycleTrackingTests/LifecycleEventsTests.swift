import CBOR
import Events
import LifecycleTracking
import PropertyBased
import Testing

@Suite("Lifecycle events")
struct LifecycleEventsTests {
    @Test("An install's CBOR decodes to the same install")
    func installedRoundTrip() throws {
        let expected = ApplicationInstalled(version: "1.2.0")
        let bytes = try CBOREncoder().encode(expected)

        let actual = try CBORDecoder().decode(ApplicationInstalled.self, from: bytes)

        #expect(actual == expected)
    }

    @Test("An update encodes as a map of its version and its previous version, and decodes back")
    func updatedRoundTrip() throws {
        let expected = ApplicationUpdated(previousVersion: "1.1.0", version: "1.2.0")
        // {"version": "1.2.0", "previousVersion": "1.1.0"}, keys in CBOR's sorted order.
        let expectedBytes: [UInt8] = [
            0xA2,
            0x67, 0x76, 0x65, 0x72, 0x73, 0x69, 0x6F, 0x6E, 0x65, 0x31, 0x2E, 0x32, 0x2E, 0x30,
            0x6F, 0x70, 0x72, 0x65, 0x76, 0x69, 0x6F, 0x75, 0x73, 0x56, 0x65, 0x72, 0x73, 0x69, 0x6F, 0x6E,
            0x65, 0x31, 0x2E, 0x31, 0x2E, 0x30,
        ]
        let bytes = try CBOREncoder().encode(expected)

        let actual = try CBORDecoder().decode(ApplicationUpdated.self, from: bytes)

        #expect(bytes == expectedBytes)
        #expect(actual == expected)
    }

    @Test("A map holding a previous version but no version doesn't decode as an update: keyNotFound names version")
    func updatedTruncated() {
        let bytes = CBOR.map([.textString("previousVersion"): .textString("1.1.0")]).encode()
        let expectedKey = "version"

        let error = #expect(throws: DecodingError.self) {
            try CBORDecoder().decode(ApplicationUpdated.self, from: bytes)
        }

        guard case .keyNotFound(let key, _) = error else {
            Issue.record("Expected keyNotFound, got \(String(describing: error))")
            return
        }
        #expect(key.stringValue == expectedKey)
    }

    @Test("An open's CBOR decodes to the same open, from the background or not", arguments: [false, true])
    func openedRoundTrip(fromBackground: Bool) throws {
        let expected = ApplicationOpened(fromBackground: fromBackground)
        let bytes = try CBOREncoder().encode(expected)

        let actual = try CBORDecoder().decode(ApplicationOpened.self, from: bytes)

        #expect(actual == expected)
    }

    @Test("Empty bytes don't decode as an open")
    func openedTruncated() {
        let bytes: [UInt8] = []

        #expect(throws: CBORError.self) {
            try CBORDecoder().decode(ApplicationOpened.self, from: bytes)
        }
    }

    @Test("A move to the background and an end encode as an empty map, and decode from one")
    func propertylessRoundTrip() throws {
        let expectedBytes: [UInt8] = [0xA0]

        let backgrounded = try CBOREncoder().encode(ApplicationBackgrounded())
        let terminated = try CBOREncoder().encode(ApplicationTerminated())
        let actualBackgrounded = try CBORDecoder().decode(ApplicationBackgrounded.self, from: expectedBytes)
        let actualTerminated = try CBORDecoder().decode(ApplicationTerminated.self, from: expectedBytes)

        #expect(backgrounded == expectedBytes)
        #expect(terminated == expectedBytes)
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

    @Test("An update encodes as the map of its two versions CBOR's value model writes, and decodes back, for any two strings")
    func updatedEncodingProperty() async {
        await propertyCheck(count: 300, input: Gen.uint8().array(of: 0...24), Gen.uint8().array(of: 0...24)) { previousBytes, versionBytes in
            let previous = String(decoding: previousBytes, as: UTF8.self)
            let version = String(decoding: versionBytes, as: UTF8.self)
            let update = ApplicationUpdated(previousVersion: previous, version: version)
            let reference = CBOR.map([.textString("previousVersion"): .textString(previous), .textString("version"): .textString(version)]).encode()

            let bytes = try? CBOREncoder().encode(update)
            let decoded = try? CBORDecoder().decode(ApplicationUpdated.self, from: reference)

            #expect(bytes == reference)
            #expect(decoded == update)
        }
    }
}
