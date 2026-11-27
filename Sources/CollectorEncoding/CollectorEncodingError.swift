/// Why ``CollectorBatchEncoder`` couldn't encode a record, which it leaves out of the batch's
/// request as a `SkippedRecord`, and `HTTPDestination` logs and reports. When it can encode no
/// record of a batch, it makes no request, and `HTTPDestination` sends nothing for the batch.
public enum CollectorEncodingError: Error, Sendable, Hashable {
    /// The tracking plan the encoder was made with has no schema of this event at this version.
    case unknownEvent(name: String, version: Int)
    /// The event isn't `Encodable`, the form its properties are read from; `@Event` makes it so.
    case notEncodable(name: String)
    /// A property's value has no JSON form: a NaN or an infinite number. `property` is empty when
    /// the event's `Encodable` conformance, one of the app's own, doesn't write a map of its
    /// properties, or throws.
    case unrepresentableValue(event: String, property: String)
    /// The record's timestamp has no ISO 8601 form: it is NaN, infinite, or further from 1970
    /// than `Int64.max` milliseconds.
    case unrepresentableTimestamp
}
