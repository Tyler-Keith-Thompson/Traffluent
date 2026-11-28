/// Why ``CollectorBatchDecoder`` couldn't read a record of a batch back, which it leaves out of the
/// decoded records as an ``UndecodedRecord``, reading the batch's other records.
public enum CollectorDecodingError: Error, Sendable, Hashable {
    /// The record isn't a JSON object.
    case notAnObject
    /// A member the encoder writes is missing, or doesn't hold what the encoder writes for it: its
    /// name (`id`, `name`, `timestamp`, `properties`, `context`, `isRedelivered` or `version`), or a
    /// member of `context` by its path (`context.session`). A `version` may be missing, but not
    /// `null`, a fraction, text or an integer outside `Int`'s range.
    case malformedMember(String)
    /// None of the decoder's event types has this `Event/name`.
    case unknownEvent(name: String)
    /// The decoder has event types of this name, but none at this version that the tracking plan
    /// has a schema of: the version the record's `version` member states, or the one a record
    /// without the member is read at, 1 when no version is readable.
    case unknownVersion(name: String, version: Int)
    /// A property doesn't hold what the event's type reads: a value of another type, an integer
    /// outside its type's range, a timestamp of another form, a value its `Refined` rule refuses,
    /// a required property that is missing, as a `Sensitive` one is once a delivery redacts it, or
    /// a `null` element of an array of non-optional `Sensitive` values a delivery redacted. A
    /// record without a `version` member that a release sent at a raised version fails this way
    /// when its properties don't fit the version it is read at. `property` is empty when the
    /// event's `Decodable` conformance, one of the app's own, failed without naming one.
    case undecodableProperty(event: String, property: String)
}
