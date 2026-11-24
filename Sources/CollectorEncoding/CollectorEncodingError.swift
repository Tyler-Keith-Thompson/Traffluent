/// Why ``CollectorBatchEncoder`` couldn't encode a batch; `HTTPDestination` then sends nothing
/// for it, and logs the error.
public enum CollectorEncodingError: Error, Sendable, Hashable {
    /// The tracking plan the encoder was made with has no schema of this event at this version.
    case unknownEvent(name: String, version: Int)
    /// The event isn't `BinaryCodable`, the form its properties are read from; `@Event` makes it so.
    case notBinaryCodable(name: String)
    /// A property's value has no JSON form: a NaN or an infinite number. `property` is empty when
    /// the event's `BinaryCodable` conformance, one of the app's own, doesn't write a map of its
    /// properties.
    case unrepresentableValue(event: String, property: String)
}
