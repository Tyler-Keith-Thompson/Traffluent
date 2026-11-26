// ScreenViewed builds on every platform, so these tests run on Linux too: a tracking plan or a
// collector there names it.
import CBOR
import Events
import SwiftUITracking
import Testing

@Suite("ScreenViewed")
struct ScreenViewedTests {
    @Test("A screen view encodes as a map of its screen's name, and decodes back")
    func roundTrip() throws {
        let expected = ScreenViewed(screen: "Checkout")
        // {"screen": "Checkout"}
        let expectedBytes: [UInt8] = [0xA1, 0x66, 0x73, 0x63, 0x72, 0x65, 0x65, 0x6E, 0x68, 0x43, 0x68, 0x65, 0x63, 0x6B, 0x6F, 0x75, 0x74]

        let bytes = try CBOREncoder().encode(expected)
        let actual = try CBORDecoder().decode(ScreenViewed.self, from: bytes)

        #expect(bytes == expectedBytes)
        #expect(actual == expected)
    }

    @Test("Its schema names the event, version 1 for analytics, with the screen's name as a required String")
    func schema() {
        let expected = EventSchema(
            name: "ScreenViewed",
            version: 1,
            consentCategory: .analytics,
            properties: [EventSchema.Property(name: "screen", typeName: "String", isOptional: false)]
        )

        let actual = ScreenViewed.schema

        #expect(actual == expected)
    }
}
