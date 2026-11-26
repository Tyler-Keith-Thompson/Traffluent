/// Why ``PostHogBatchEncoder`` couldn't encode a record, which it leaves out of the batch's body
/// as a ``PostHogSkippedRecord``. When it can encode no record of a batch,
/// ``PostHogBatchEncoder/encode(_:)`` throws the first one's, and `HTTPDestination` sends nothing
/// for the batch and logs the error.
public enum PostHogEncodingError: Error, Sendable, Hashable {
    /// The tracking plan the encoder was made with has no schema of this event at this version.
    case unknownEvent(name: String, version: Int)
    /// The event's name starts with `$`, which PostHog keeps for its own events (`$pageview`,
    /// `$identify`, `$set`).
    case reservedEventName(name: String)
    /// The event isn't `Encodable`, the form its properties are read from; `@Event` makes it so.
    case notEncodable(name: String)
    /// A property's value has no JSON form: a NaN or an infinite number. `property` is empty when
    /// the event's `Encodable` conformance, one of the app's own, doesn't write a map of its
    /// properties, or throws.
    case unrepresentableValue(event: String, property: String)
}
