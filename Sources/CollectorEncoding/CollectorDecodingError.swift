/// Why ``CollectorBatchDecoder`` couldn't read a record of a batch back, which it leaves out of the
/// decoded records as an ``UndecodedRecord``, reading the batch's other records.
public enum CollectorDecodingError: Error, Sendable, Hashable {
    /// The record isn't a JSON object.
    case notAnObject
    /// A member the encoder writes is missing, or doesn't hold what the encoder writes for it: its
    /// name (`id`, `name`, `timestamp`, `properties`, `context` or `isRedelivered`), or a member of
    /// `context` by its path (`context.session`).
    case malformedMember(String)
    /// None of the decoder's event types has this `Event/name`.
    case unknownEvent(name: String)
    /// The decoder's event type of this name is at a version, its `Event/schemaVersion`, that the
    /// tracking plan has no schema of.
    case unknownVersion(name: String, version: Int)
    /// A property doesn't hold what the event's type reads: a value of another type, an integer
    /// outside its type's range, a timestamp of another form, a value its `Refined` rule refuses,
    /// a required property that is missing, as a `Sensitive` one is once a delivery redacts it, or
    /// a `null` element of an array of non-optional `Sensitive` values a delivery redacted. A
    /// record of an earlier version of the event than the decoder's type fails this way when its
    /// properties don't fit the type. `property` is empty when the
    /// event's `Decodable` conformance, one of the app's own, failed without naming one.
    case undecodableProperty(event: String, property: String)
}
