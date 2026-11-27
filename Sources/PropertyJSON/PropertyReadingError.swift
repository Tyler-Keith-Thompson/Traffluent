/// Why a record's properties couldn't be read as JSON.
public enum PropertyReadingError: Error, Sendable, Hashable {
    /// The tracking plan the reader was made with has no schema of this event at this version.
    case unknownEvent(name: String, version: Int)
    /// The event isn't `Encodable`, the form its properties are read from; `@Event` makes it so.
    case notEncodable(name: String)
    /// A property's value has no JSON form: a NaN or an infinite number. `property` is empty when
    /// the event's `Encodable` conformance, one of the app's own, doesn't write a map of its
    /// properties, or throws.
    case unrepresentableValue(event: String, property: String)
}
