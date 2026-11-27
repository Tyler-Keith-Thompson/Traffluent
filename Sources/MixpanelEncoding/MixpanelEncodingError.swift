/// Why ``MixpanelBatchEncoder`` couldn't send a record, which it leaves out of the batch's
/// requests as a `SkippedRecord`, and `HTTPDestination` reports as a drop. When it can encode no
/// record of a batch, it makes no request, and `HTTPDestination` sends nothing for the batch.
public enum MixpanelEncodingError: Error, Sendable, Hashable {
    /// The tracking plan the encoder was made with has no schema of this event at this version.
    case unknownEvent(name: String, version: Int)
    /// The event's name starts with `$`, as Mixpanel's own events' names do. Some of them
    /// (`$identify`, `$create_alias`) change who Mixpanel attributes events to.
    case reservedEventName(name: String)
    /// A property's name is one Mixpanel reads for itself: one starting with `$` (`$insert_id`,
    /// `$user_id`, `$ignore` and Mixpanel's default properties), or `token`, `time`,
    /// `distinct_id`, `ip` or `bucket`. Sent, it would change how Mixpanel ingests the event, or be
    /// lost under a value the encoder writes. `property` is the first such name in the order of
    /// the names' UTF-8 bytes. Rename the property, raising the event's schema version, to send
    /// the event.
    case reservedPropertyName(event: String, property: String)
    /// The event isn't `Encodable`, the form its properties are read from; `@Event` makes it so.
    case notEncodable(name: String)
    /// A property's value has no JSON form: a NaN or an infinite number. `property` is empty when
    /// the event's `Encodable` conformance, one of the app's own, doesn't write a map of its
    /// properties, or throws.
    case unrepresentableValue(event: String, property: String)
    /// The record's timestamp is no `time` Mixpanel takes: it is NaN, infinite, further from 1970
    /// than `Int64.max` milliseconds, or before 1971-01-01, which Mixpanel rejects.
    case unrepresentableTimestamp
    /// The event would have `count` properties, 255 or more, which Mixpanel drops an event for.
    /// `count` includes the members the encoder writes (`token`, `time`, `distinct_id`,
    /// `$insert_id`, `ip`, `$device_id` for a record with a session) and the default properties of
    /// the record's context.
    case tooManyProperties(event: String, count: Int)
    /// An array in a property's value has `count` elements, 255 or more, which Mixpanel drops an
    /// event for. `property` is the event's property that holds it, the first such one in the
    /// order of the names' UTF-8 bytes.
    case tooManyArrayElements(event: String, property: String, count: Int)
    /// A property's value nests objects more than 3 deep, which Mixpanel drops an event for. An
    /// object as the property's value is 1 deep, an object in it 2; arrays add no depth.
    /// `property` is the first such property in the order of the names' UTF-8 bytes.
    case nestedTooDeeply(event: String, property: String)
    /// The event's JSON is `byteCount` bytes, more than Mixpanel takes for one event, or than one
    /// request holds beside the envelope (``MixpanelBatchEncoder/batchLimit``); only
    /// ``MixpanelBatchEncoder/requests(for:)`` leaves a record out for it.
    case oversized(byteCount: Int)
}
