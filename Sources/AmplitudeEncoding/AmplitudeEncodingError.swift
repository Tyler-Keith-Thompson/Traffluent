/// Why ``AmplitudeBatchEncoder`` couldn't send a record, which it leaves out of the batch's
/// requests as a `SkippedRecord`, and `HTTPDestination` reports as a drop. When it can encode no
/// record of a batch, it makes no request, and `HTTPDestination` sends nothing for the batch.
public enum AmplitudeEncodingError: Error, Sendable, Hashable {
    /// The tracking plan the encoder was made with has no schema of this event at this version.
    case unknownEvent(name: String, version: Int)
    /// The event's name is one Amplitude keeps for its own events: one starting with
    /// `[Amplitude]` (`[Amplitude] Start Session`), `$identify` or `$groupidentify`.
    case reservedEventName(name: String)
    /// The event isn't `Encodable`, the form its properties are read from; `@Event` makes it so.
    case notEncodable(name: String)
    /// A property's value has no JSON form: a NaN or an infinite number. `property` is empty when
    /// the event's `Encodable` conformance, one of the app's own, doesn't write a map of its
    /// properties, or throws.
    case unrepresentableValue(event: String, property: String)
    /// The record's timestamp has no epoch-milliseconds form, the only `time` Amplitude takes: it
    /// is NaN, infinite, or further from 1970 than `Int64.max` milliseconds.
    case unrepresentableTimestamp
    /// The event's JSON is `byteCount` bytes, more than one request holds beside the envelope
    /// (``AmplitudeBatchEncoder/batchLimit``); only ``AmplitudeBatchEncoder/requests(for:)``
    /// leaves a record out for it.
    case oversized(byteCount: Int)
}
