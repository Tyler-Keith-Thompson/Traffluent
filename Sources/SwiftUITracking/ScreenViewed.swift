#if canImport(SwiftUI)
public import Events
public import Persistence

/// Someone viewed the screen named ``screen``: what `trackScreen(_:)` tracks each time its view
/// appears.
///
/// It is `BinaryCodable`, so a store keeps it once its `events` list `ScreenViewed.self`, and its
/// ``schema`` goes in a tracking plan beside the app's own events.
public struct ScreenViewed: Event, BinaryCodable, Hashable {
    /// The viewed screen's name.
    public var screen: String

    /// The schema of a screen view: version 1, collected for analytics, with one property, the
    /// screen's name.
    public static let schema = EventSchema(
        name: name,
        version: 1,
        consentCategory: consentCategory,
        properties: [EventSchema.Property(name: "screen", typeName: "String", isOptional: false)]
    )

    /// The event for a view of the screen named `screen`.
    ///
    /// - Parameter screen: The viewed screen's name.
    public init(screen: String) {
        self.screen = screen
    }

    /// Writes a map of the screen's name (`screen`) to `encoder`.
    ///
    /// - Parameter encoder: Where the bytes go.
    public func encode(to encoder: inout BinaryEncoder) {
        encoder.encodeMap { map in
            map.encode(screen, forKey: "screen")
        }
    }

    /// Reads the screen's name from `decoder`.
    ///
    /// - Parameter decoder: Where the bytes come from.
    /// - Throws: `BinaryDecodingError` when the bytes don't hold a map with a name.
    public init(from decoder: inout BinaryDecoder) throws(BinaryDecodingError) {
        var map = try decoder.decodeMap()
        screen = try map.decode(forKey: "screen")
    }
}
#endif
