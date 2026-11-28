/// Why an event couldn't be read back from its properties as JSON: the property whose value isn't
/// one the event's `Decodable` conformance reads, or is missing.
package struct UndecodableProperty: Error, Sendable, Hashable {
    /// The property's name; empty when the event's conformance failed without naming one.
    package var property: String

    /// The error of `property`.
    package init(property: String) {
        self.property = property
    }
}
