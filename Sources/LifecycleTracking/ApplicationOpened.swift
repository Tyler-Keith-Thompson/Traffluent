public import Events
public import Persistence

/// The app was opened: launched, or brought back to the foreground when ``fromBackground``. What
/// `trackLifecycle` tracks as it starts, and each time the app returns from the background.
///
/// It is `BinaryCodable`, so a store keeps it once its `events` list `ApplicationOpened.self`,
/// and its ``schema`` goes in a tracking plan beside the app's own events.
public struct ApplicationOpened: Event, BinaryCodable, Hashable {
    /// Whether the app came back from the background, rather than being launched.
    public var fromBackground: Bool

    /// The schema of an open: version 1, collected for analytics, with one property, whether the
    /// app came back from the background.
    public static let schema = EventSchema(
        name: name,
        version: schemaVersion,
        consentCategory: consentCategory,
        properties: [EventSchema.Property(name: "fromBackground", typeName: "Bool", isOptional: false)]
    )

    /// The event for an open, from the background or not.
    ///
    /// - Parameter fromBackground: Whether the app came back from the background.
    public init(fromBackground: Bool) {
        self.fromBackground = fromBackground
    }

    /// Writes a map of whether the app came from the background (`fromBackground`) to `encoder`.
    ///
    /// - Parameter encoder: Where the bytes go.
    public func encode(to encoder: inout BinaryEncoder) {
        encoder.encodeMap { map in
            map.encode(fromBackground, forKey: "fromBackground")
        }
    }

    /// Reads whether the app came from the background from `decoder`.
    ///
    /// - Parameter decoder: Where the bytes come from.
    /// - Throws: `BinaryDecodingError` when the bytes don't hold a map with that `Bool`.
    public init(from decoder: inout BinaryDecoder) throws(BinaryDecodingError) {
        var map = try decoder.decodeMap()
        fromBackground = try map.decode(forKey: "fromBackground")
    }
}
