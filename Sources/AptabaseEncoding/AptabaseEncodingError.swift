/// Why ``AptabaseBatchEncoder`` couldn't send a record, which it leaves out of the batch's requests
/// as a `SkippedRecord`, and `HTTPDestination` reports as a drop. When it can encode no record of a
/// batch, it makes no request, and `HTTPDestination` sends nothing for the batch.
///
/// Aptabase answers 400 to a whole request when one event breaks a rule of its model (its name or
/// a system property too long), drops an event with a property it refuses or a time too old while
/// answering 200, and cuts a long string short, so the encoder leaves out each record that breaks
/// one of those rules and reports it, rather than lose the records sent beside it, lose it without
/// a report, or store a value cut short. Lengths are counted in UTF-16 code units, as .NET, which
/// Aptabase's server is written in, counts a string's length.
public enum AptabaseEncodingError: Error, Sendable, Hashable {
    /// The tracking plan the encoder was made with has no schema of this event at this version.
    case unknownEvent(name: String, version: Int)
    /// The event's name is only whitespace, or longer than the 60 characters Aptabase takes; it
    /// refuses the whole request holding one.
    case invalidEventName(name: String)
    /// A property's name is empty or only whitespace, as a key of a dictionary property can be:
    /// Aptabase drops the event holding one. A nested value's property is named after its path,
    /// joined by `.` (`cart.size`, `tags.0`). `property` is the first such name in the order of the
    /// names' UTF-8 bytes.
    case emptyPropertyName(event: String, property: String)
    /// A property's name, joined by `.` from its path when it is nested, is longer than the 40
    /// characters Aptabase takes: it drops the event holding one. `property` is the first such
    /// name in the order of the names' UTF-8 bytes.
    case propertyNameTooLong(event: String, property: String)
    /// The string value of `property` is `length` characters, more than the 180 Aptabase stores:
    /// it would cut the value short and end it with `...`. `property` is the first such property in
    /// the order of the names' UTF-8 bytes.
    case propertyValueTooLong(event: String, property: String, length: Int)
    /// The number `property` holds is too large for Aptabase, which stores a number as a .NET
    /// `decimal`: its magnitude is 2⁹⁶, about 7.9 × 10²⁸, or more. Aptabase fails the whole
    /// request holding one. `property` is the first such property in the order of the names'
    /// UTF-8 bytes.
    case numberOutOfRange(event: String, property: String)
    /// Two of the event's values flatten to one property's name, such as a property `cart.size`
    /// beside a property `cart` holding `size`.
    case propertyNameCollision(event: String, property: String)
    /// The event isn't `Encodable`, the form its properties are read from; `@Event` makes it so.
    case notEncodable(name: String)
    /// A property's value has no JSON form: a NaN or an infinite number. `property` is empty when
    /// the event's `Encodable` conformance, one of the app's own, doesn't write a map of its
    /// properties, or throws.
    case unrepresentableValue(event: String, property: String)
    /// The record's timestamp is NaN, infinite, or outside the years 1 to 9999, which Aptabase's
    /// server can't read as a time; it refuses the whole request holding one.
    case unrepresentableTimestamp
    /// The record was tracked more than 23 hours before the batch was encoded, or the clock the
    /// encoder reads gave a NaN or infinite time. Aptabase drops an event more than a day old while
    /// answering 200; the hour to spare is for a queue on the server and clocks that disagree.
    case timestampOutsideWindow
    /// The event's JSON is `byteCount` bytes, more than a request of the record alone can hold:
    /// by default, the 1,000,000 bytes of a request (``AptabaseBatchEncoder/batchLimit``) less the
    /// array around the events: 999,998 bytes. Only ``AptabaseBatchEncoder/requests(for:)`` leaves
    /// a record out for it.
    case oversized(byteCount: Int)
}
