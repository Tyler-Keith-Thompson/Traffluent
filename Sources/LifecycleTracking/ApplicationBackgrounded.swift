public import Events
public import Persistence

/// The app moved to the background: what `trackLifecycle` tracks each time the app leaves the
/// foreground (on macOS, each time it stops being the active app).
///
/// It is `BinaryCodable`, so a store keeps it once its `events` list `ApplicationBackgrounded.self`,
/// and its schema goes in a tracking plan beside the app's own events. It has no properties.
public struct ApplicationBackgrounded: Event, BinaryCodable, Hashable {
    /// The schema of a move to the background: version 1, collected for analytics, with no properties.
    public static let schema = EventSchema(
        name: name,
        version: 1,
        consentCategory: consentCategory,
        properties: []
    )

    /// The event for a move to the background.
    public init() {}

    /// Writes an empty map: the event has no properties.
    ///
    /// - Parameter encoder: Where the bytes go.
    public func encode(to encoder: inout BinaryEncoder) {
        encoder.encodeMap { _ in }
    }

    /// Reads a map, skipping any entries: the event has no properties.
    ///
    /// - Parameter decoder: Where the bytes come from.
    /// - Throws: `BinaryDecodingError` when the bytes don't hold a map.
    public init(from decoder: inout BinaryDecoder) throws(BinaryDecodingError) {
        _ = try decoder.decodeMap()
    }
}
