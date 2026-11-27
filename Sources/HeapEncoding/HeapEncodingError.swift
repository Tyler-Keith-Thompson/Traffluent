/// Why ``HeapBatchEncoder`` couldn't send a record, which it leaves out of the batch's requests as
/// a `SkippedRecord`, and `HTTPDestination` reports as a drop. When it can encode no record of a
/// batch, it makes no request, and `HTTPDestination` sends nothing for the batch.
///
/// Heap's track API answers 400 to a request it can't take, and its docs don't say what it does
/// with a value past its limits, so the encoder leaves out each record that breaks one and reports
/// it, rather than risk Heap refusing the records sent beside it or storing a value cut short.
/// Lengths are counted in UTF-16 code units, as JavaScript counts a string's characters.
public enum HeapEncodingError: Error, Sendable, Hashable {
    /// The tracking plan the encoder was made with has no schema of this event at this version.
    case unknownEvent(name: String, version: Int)
    /// The event's name is longer than the 1,024 characters Heap takes.
    case invalidEventName(name: String)
    /// A property's name is one Heap reserves, `user_id`, `session_id` or `screen_name`, spelled
    /// exactly so: the first two are fields of a track request, and the last is the screen name
    /// Heap's mobile SDKs capture. A nested value's property is named after its path, joined by `.`
    /// (`cart.size`, `tags.0`). `property` is the first such name in the order of the names' UTF-8
    /// bytes. Rename the property, raising the event's schema version, to send the event.
    case reservedPropertyName(event: String, property: String)
    /// A property's name, joined by `.` from its path when it is nested, is 1,024 characters or
    /// longer: Heap takes a key of fewer. `property` is the first such name in the order of the
    /// names' UTF-8 bytes.
    case propertyNameTooLong(event: String, property: String)
    /// The string value of `property` is `length` characters, 1,024 or more: Heap takes a value of
    /// fewer. `property` is the first such property in the order of the names' UTF-8 bytes.
    case propertyValueTooLong(event: String, property: String, length: Int)
    /// Two of the event's values flatten to one property's name, such as a property `cart.size`
    /// beside a property `cart` holding `size`.
    case propertyNameCollision(event: String, property: String)
    /// The event isn't `Encodable`, the form its properties are read from; `@Event` makes it so.
    case notEncodable(name: String)
    /// A property's value has no JSON form: a NaN or an infinite number. `property` is empty when
    /// the event's `Encodable` conformance, one of the app's own, doesn't write a map of its
    /// properties, or throws.
    case unrepresentableValue(event: String, property: String)
    /// The record's timestamp is NaN, infinite, or outside the years 1 to 9999, which have no
    /// four-digit ISO 8601 year for Heap to parse.
    case unrepresentableTimestamp
    /// The event's JSON is `byteCount` bytes, more than a request of the record alone can hold:
    /// by default, the 1,000,000 bytes of a request (``HeapBatchEncoder/batchLimit``) less the
    /// object around the events, which holds the app ID: 999,967 bytes for an app ID of 8 digits.
    /// Only ``HeapBatchEncoder/requests(for:)`` leaves a record out for it.
    case oversized(byteCount: Int)
}
