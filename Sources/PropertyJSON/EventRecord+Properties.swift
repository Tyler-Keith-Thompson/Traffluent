package import Events
import Persistence
package import TrackingPlans

extension EventRecord {
    /// The event's properties as JSON, read from its `BinaryCodable` form through `types`.
    ///
    /// - Parameters:
    ///   - types: Each property's type as its schema writes it (`EventSchema/propertyTypes`).
    ///   - writingSensitiveValues: Whether a `Sensitive` value is written as its value; when
    ///     `false`, it is left out, and an element of an array is `null`.
    /// - Throws: ``PropertyReadingError/notBinaryCodable(name:)`` for an event that isn't
    ///   `BinaryCodable`; ``PropertyReadingError/unrepresentableValue(event:property:)`` for a value
    ///   JSON can't hold.
    package func properties(types: [String: WrittenType?], writingSensitiveValues: Bool) throws(PropertyReadingError) -> [String: JSON] {
        guard let event = event as? any BinaryCodable else {
            throw .notBinaryCodable(name: name)
        }
        // The store's encoder only when sensitive values are written; otherwise each is written as
        // `undefined`, which the reader leaves out.
        var encoder = BinaryEncoder(writingSensitiveValues: writingSensitiveValues)
        encoder.encode(event)
        var reader = PropertyReader(bytes: encoder.bytes)
        return try reader.properties(types: types, event: name)
    }
}
