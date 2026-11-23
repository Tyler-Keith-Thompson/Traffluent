public import Events
public import Persistence

/// The app is about to end: what `trackLifecycle` tracks where the platform reports it (on iOS,
/// iPadOS, tvOS, visionOS and macOS, as the app terminates), and as its `finish()` is called.
///
/// It is `BinaryCodable`, so a store keeps it once its `events` list `ApplicationTerminated.self`,
/// and its schema goes in a tracking plan beside the app's own events. It has no properties.
public struct ApplicationTerminated: Event, BinaryCodable, Hashable {
    /// The schema of an end: version 1, collected for analytics, with no properties.
    public static let schema = EventSchema(
        name: name,
        version: 1,
        consentCategory: consentCategory,
        properties: []
    )

    /// The event for an end.
    public init() {}

    /// Writes nothing: the event has no properties.
    ///
    /// - Parameter encoder: Where the bytes would go.
    public func encode(to encoder: inout BinaryEncoder) {}

    /// Reads nothing: the event has no properties.
    ///
    /// - Parameter decoder: Where the bytes would come from.
    public init(from decoder: inout BinaryDecoder) throws(BinaryDecodingError) {}
}
