/// Why ``SegmentSpecBatchEncoder`` couldn't send a record, which it leaves out of the batch's
/// requests as a `SkippedRecord`, and `HTTPDestination` reports as a drop. When it can encode no
/// record of a batch, it makes no request, and `HTTPDestination` sends nothing for the batch.
public enum SegmentSpecEncodingError: Error, Sendable, Hashable {
    /// The tracking plan the encoder was made with has no schema of this event at this version.
    case unknownEvent(name: String, version: Int)
    /// The event's name is one of Customer.io's semantic events, which act on the person rather
    /// than record what they did: `User Deleted`, `User Suppressed`, `User Unsuppressed`,
    /// `Device Created or Updated`, `Device Deleted`, `Object Deleted`, `Relationship Deleted` or
    /// `Report Delivery Event`. Rename the event, with a new name in `@Event(name:)`, to send it.
    case reservedEventName(name: String)
    /// The event isn't `Encodable`, the form its properties are read from; `@Event` makes it so.
    case notEncodable(name: String)
    /// A property's value has no JSON form: a NaN or an infinite number. `property` is empty when
    /// the event's `Encodable` conformance, one of the app's own, doesn't write a map of its
    /// properties, or throws.
    case unrepresentableValue(event: String, property: String)
    /// The record's timestamp has no ISO 8601 form the spec takes: it is NaN, infinite, before
    /// 1583-01-01, the first year wholly in the Gregorian calendar ISO 8601 counts in, or from
    /// 10000-01-01 on, which has no four-digit year.
    case unrepresentableTimestamp
    /// The call's JSON is `byteCount` bytes, more than the endpoint takes for one call, or than
    /// one request holds beside the envelope (``SegmentSpecBatchEncoder/batchLimit``); only
    /// ``SegmentSpecBatchEncoder/requests(for:)`` leaves a record out for it.
    case oversized(byteCount: Int)
}
