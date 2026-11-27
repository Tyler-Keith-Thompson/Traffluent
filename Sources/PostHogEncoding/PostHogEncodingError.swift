/// Why ``PostHogBatchEncoder`` couldn't send a record, which it leaves out of the batch's requests
/// as a `SkippedRecord`, and `HTTPDestination` reports as a drop. When it can encode no record of
/// a batch, it makes no request, and `HTTPDestination` sends nothing for the batch.
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
    /// The event's JSON is `byteCount` bytes, more than PostHog stores of one event, or than one
    /// request holds beside the envelope (``PostHogBatchEncoder/batchLimit``); only
    /// ``PostHogBatchEncoder/requests(for:)`` leaves a record out for it.
    case oversized(byteCount: Int)
}
