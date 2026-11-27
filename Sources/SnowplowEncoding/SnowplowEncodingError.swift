/// Why ``SnowplowBatchEncoder`` couldn't send a record, which it leaves out of the batch's
/// requests as a `SkippedRecord`, and `HTTPDestination` reports as a drop. When it can encode no
/// record of a batch, it makes no request, and `HTTPDestination` sends nothing for the batch.
///
/// A Snowplow collector answers 200 to every request it can read, and its pipeline validates the
/// events later, writing those that fail as failed events rather than into the warehouse, so the
/// encoder leaves out each record it knows would fail, and reports it.
public enum SnowplowEncodingError: Error, Sendable, Hashable {
    /// The tracking plan the encoder was made with has no schema of this event at this version.
    case unknownEvent(name: String, version: Int)
    /// The event's schema has no Iglu URI: its name holds a character other than an ASCII letter,
    /// digit, `-` or `_` (a space, a `.`, a letter outside ASCII), or its version is below 1, which
    /// no SchemaVer has. Rename the event, with a new name in `@Event(name:)` and a raised
    /// version, to send it.
    case invalidSchemaKey(name: String, version: Int)
    /// The event isn't `Encodable`, the form its properties are read from; `@Event` makes it so.
    case notEncodable(name: String)
    /// A property's value has no JSON form: a NaN or an infinite number. `property` is empty when
    /// the event's `Encodable` conformance, one of the app's own, doesn't write a map of its
    /// properties, or throws.
    case unrepresentableValue(event: String, property: String)
    /// The record's timestamp is NaN, infinite, or outside the years 0 to 9999, which Snowplow's
    /// enrichment refuses, failing the event.
    case unrepresentableTimestamp
    /// The event's JSON is `byteCount` bytes, more than the encoder's limit lets one record hold:
    /// 150,000 bytes by default (``SnowplowBatchEncoder/batchLimit``), within the smallest of a
    /// pipeline's streams. Only ``SnowplowBatchEncoder/requests(for:)`` leaves a record out for it.
    case oversized(byteCount: Int)
}
