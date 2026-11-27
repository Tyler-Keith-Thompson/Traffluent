// Compiled for macOS and Linux alone, as the factory is (HTTPDestination+GoogleAnalytics.swift), so
// nothing in this module can write a Measurement Protocol request in an app for iOS, iPadOS, tvOS,
// watchOS, visionOS or Mac Catalyst.
#if os(macOS) || os(Linux)
/// Why ``GoogleAnalyticsBatchEncoder`` couldn't send a record, which it leaves out of the batch's
/// requests as a `SkippedRecord`, and `HTTPDestination` reports as a drop. When it can encode no
/// record of a batch, it makes no request, and `HTTPDestination` sends nothing for the batch.
///
/// The Measurement Protocol answers 2xx to a request whose events break its rules. Under its
/// default, relaxed validation it stores such an event without the parameter that breaks a rule,
/// or under a name it never checked, so the encoder leaves out each record that would break one
/// and reports it, rather than have Google Analytics store an event other than the one tracked.
public enum GoogleAnalyticsEncodingError: Error, Sendable, Hashable {
    /// The tracking plan the encoder was made with has no schema of this event at this version.
    case unknownEvent(name: String, version: Int)
    /// The event's name isn't one Google Analytics takes: it is empty or longer than 40 bytes of
    /// UTF-8, doesn't start with a letter, or holds a character other than a letter, a number
    /// or `_`. Letters and numbers of any script count.
    case invalidEventName(name: String)
    /// The event's name is one Google Analytics keeps for its own events (`session_start`,
    /// `first_visit`, `error` and the rest of its reserved names), or one it takes only from an app
    /// stream (`screen_view`, `ad_impression`, `in_app_purchase`).
    case reservedEventName(name: String)
    /// A parameter's name isn't one Google Analytics takes: it is empty or longer than 40 bytes of
    /// UTF-8, doesn't start with a letter, or holds a character other than a letter, a number
    /// or `_`. A nested value's parameter is named after its path, joined by `_`
    /// (`cart_size`, `tags_0`). `parameter` is the first such name in the order of the names'
    /// UTF-8 bytes.
    case invalidParameterName(event: String, parameter: String)
    /// A parameter's name is one Google Analytics keeps: `firebase_conversion`, one starting with
    /// `firebase_`, `ga_` or `google_`, or `session_id`, which the encoder writes itself.
    /// `parameter` is the first such name in the order of the names' UTF-8 bytes. Rename the
    /// property, raising the event's schema version, to send the event.
    case reservedParameterName(event: String, parameter: String)
    /// Two of the event's values flatten to one parameter's name, such as a property `cart_size`
    /// beside a property `cart` holding `size`.
    case parameterNameCollision(event: String, parameter: String)
    /// The event would have `count` parameters, more than the 25 Google Analytics takes. `count`
    /// includes `session_id`, which the encoder adds for a record with a session, and a nested
    /// value's parameters, one for each value it holds.
    case tooManyParameters(event: String, count: Int)
    /// A parameter's string is `byteCount` bytes of UTF-8, more than the 100 a standard Google
    /// Analytics property takes. `parameter` is the first such name in the order of the names'
    /// UTF-8 bytes.
    case parameterValueTooLong(event: String, parameter: String, byteCount: Int)
    /// The event isn't `Encodable`, the form its properties are read from; `@Event` makes it so.
    case notEncodable(name: String)
    /// A property's value has no JSON form: a NaN or an infinite number. `property` is empty when
    /// the event's `Encodable` conformance, one of the app's own, doesn't write a map of its
    /// properties, or throws.
    case unrepresentableValue(event: String, property: String)
    /// The record's timestamp has no `timestamp_micros` form: it is NaN, infinite, or further from
    /// 1970 than `Int64.max` microseconds.
    case unrepresentableTimestamp
    /// The record's timestamp is more than 71 hours before, or more than 15 minutes after, the
    /// time its batch was encoded. Google Analytics stores an event from more than 72 hours back
    /// as if it happened 72 hours ago, the hour to spare is for the request to reach Google and
    /// clocks that disagree, and its validation server refuses one from further ahead.
    case timestampOutsideWindow
    /// The event's JSON is `byteCount` bytes, more than one request holds beside the envelope
    /// (``GoogleAnalyticsBatchEncoder/batchLimit``); only ``GoogleAnalyticsBatchEncoder/requests(for:)``
    /// leaves a record out for it.
    case oversized(byteCount: Int)
}
#endif
