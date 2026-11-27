/// Why ``MatomoBatchEncoder`` couldn't send a record, which it leaves out of the batch's requests
/// as a `SkippedRecord`, and `HTTPDestination` reports as a drop. When it can encode no record of a
/// batch, it makes no request, and `HTTPDestination` sends nothing for the batch.
///
/// Matomo answers 200 to a bulk request whatever its tracking requests hold, and stores no event
/// it refuses, so the encoder leaves out each record Matomo would refuse, or would store other
/// than it is, and reports it, rather than have it counted as delivered and lost.
public enum MatomoEncodingError: Error, Sendable, Hashable {
    /// The tracking plan the encoder was made with has no schema of this event at this version.
    case unknownEvent(name: String, version: Int)
    /// The event's name can't be an event's action: it is empty once Matomo removes its line
    /// breaks and trims it, which Matomo refuses, or longer than the 4,096 characters Matomo
    /// stores of an action, which it would cut short.
    case invalidEventName(name: String)
    /// The event isn't `Encodable`, the form its properties are read from; `@Event` makes it so.
    case notEncodable(name: String)
    /// A property's value has no JSON form: a NaN or an infinite number. `property` is empty when
    /// the event's `Encodable` conformance, one of the app's own, doesn't write a map of its
    /// properties, or throws.
    case unrepresentableValue(event: String, property: String)
    /// The record's timestamp is NaN, infinite, or too far from 1970 for whole seconds of `Int64`.
    case unrepresentableTimestamp
    /// The record was tracked more than 23 hours before, or after, the batch was encoded, or the
    /// clock the encoder reads gave a time that is NaN or infinite. Matomo takes a time more than
    /// a day old only with a `token_auth`, which an app never holds, and refuses a time more than a
    /// day ahead; the hour to spare is for the request to arrive.
    case timestampOutsideWindow
    /// The value of `property` for dimension `dimension` is `length` characters as Matomo stores it,
    /// more than the 250 Matomo keeps of a custom dimension's value.
    case dimensionValueTooLong(event: String, property: String, dimension: Int, length: Int)
    /// The record's tracking request, as a JSON string, is `byteCount` bytes, more than a request
    /// of the record alone can hold: 999,985 bytes by default, the 1,000,000 bytes of a request
    /// (``MatomoBatchEncoder/batchLimit``) less the 15 of `{"requests":[` and `]}`. Only ``MatomoBatchEncoder/requests(for:)`` leaves a
    /// record out for it.
    case oversized(byteCount: Int)
}
