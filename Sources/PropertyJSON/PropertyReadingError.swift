/// Why an event's properties couldn't be read as JSON.
package enum PropertyReadingError: Error, Sendable, Hashable {
    /// The event isn't `BinaryCodable`, the form its properties are read from; `@Event` makes it so.
    case notBinaryCodable(name: String)
    /// A property's value has no JSON form: a NaN or an infinite number. `property` is empty when
    /// the event's `BinaryCodable` conformance, one of the app's own, doesn't write a map of its
    /// properties.
    case unrepresentableValue(event: String, property: String)
}
