/// Why ``TelemetryDeckBatchEncoder`` couldn't send a record, which it leaves out of the batch's
/// requests as a `SkippedRecord`, and `HTTPDestination` reports as a drop. When it can encode no
/// record of a batch, it makes no request, and `HTTPDestination` sends nothing for the batch.
///
/// TelemetryDeck checks a whole request before it stores any of it, and answers 422 when one
/// event breaks a rule, so the encoder leaves out each record that would break one and reports
/// it, rather than have TelemetryDeck refuse the records sent beside it.
public enum TelemetryDeckEncodingError: Error, Sendable, Hashable {
    /// The tracking plan the encoder was made with has no schema of this event at this version.
    case unknownEvent(name: String, version: Int)
    /// The event's name isn't a `type` TelemetryDeck takes: it is empty, or holds a character other
    /// than an ASCII letter, digit, `.`, `_` or `-`.
    case invalidEventName(name: String)
    /// The event's name starts with `TelemetryDeck.`, in any case: the scope TelemetryDeck
    /// reserves for its SDKs' events and parameters.
    case reservedEventName(name: String)
    /// A parameter's name isn't a key TelemetryDeck takes: it is empty, or holds a character other
    /// than an ASCII letter, digit, `.`, `_` or `-`. A nested value's parameter is named after its
    /// path, joined by `.` (`cart.size`, `tags.0`). `parameter` is the first such name in the
    /// order of the names' UTF-8 bytes.
    case invalidParameterName(event: String, parameter: String)
    /// A parameter's name can't be sent: it starts with `TelemetryDeck.`, in any case, the scope
    /// TelemetryDeck reserves for its SDKs' parameters and its server's, or it is one of an Ingest
    /// API v3 event's own members (`appID`, `clientUser`, `receivedAt`, `type`, `sessionID`,
    /// `isTestMode`, `floatValue`), spelled exactly so, which the parameter would replace in the
    /// flat event. `parameter` is the first such name in the order of the names' UTF-8 bytes.
    /// Rename the property, raising the event's schema version, to send the event.
    case reservedParameterName(event: String, parameter: String)
    /// Two of the event's values flatten to one parameter's name, such as a property `cart.size`
    /// beside a property `cart` holding `size`.
    case parameterNameCollision(event: String, parameter: String)
    /// The event isn't `Encodable`, the form its properties are read from; `@Event` makes it so.
    case notEncodable(name: String)
    /// A property's value has no JSON form: a NaN or an infinite number. `property` is empty when
    /// the event's `Encodable` conformance, one of the app's own, doesn't write a map of its
    /// properties, or throws.
    case unrepresentableValue(event: String, property: String)
    /// The record's timestamp is NaN, infinite, or outside the years 1 to 9999, which TelemetryDeck
    /// refuses as a `receivedAt`.
    case unrepresentableTimestamp
    /// The event's JSON is `byteCount` bytes, more than the encoder's limit lets one record hold:
    /// 333,333 bytes by default (``TelemetryDeckBatchEncoder/batchLimit``), a third of
    /// TelemetryDeck's 1,000,000. Only ``TelemetryDeckBatchEncoder/requests(for:)``
    /// leaves a record out for it.
    case oversized(byteCount: Int)
}
