// ScreenViewed is declared where SwiftUI is, so its tests run on Apple platforms; Bazel runs the
// target on the Mac alone.
#if canImport(SwiftUI)
import Events
import Persistence
import SwiftUITracking
import Testing

@Suite("ScreenViewed")
struct ScreenViewedTests {
    @Test("A screen view's bytes decode to the same screen view, with none left over")
    func roundTrip() throws {
        let expected = ScreenViewed(screen: "Checkout")
        var encoder = BinaryEncoder()
        expected.encode(to: &encoder)
        var decoder = BinaryDecoder(encoder.bytes)

        let actual = try ScreenViewed(from: &decoder)

        #expect(actual == expected)
        #expect(decoder.isAtEnd)
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
#endif
