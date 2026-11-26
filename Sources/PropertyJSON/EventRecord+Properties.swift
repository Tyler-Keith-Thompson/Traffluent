internal import CBOR
package import Events
package import TrackingPlans

extension EventRecord {
    /// The event's properties as JSON, read from its `Encodable` form, as CBOR, through `types`.
    ///
    /// - Parameters:
    ///   - types: Each property's type as its schema writes it (`EventSchema/propertyTypes`).
    ///   - writingSensitiveValues: Whether a `Sensitive` value is written as its value; when
    ///     `false`, it is left out, and an element of an array is `null`.
    /// - Throws: ``PropertyReadingError/notEncodable(name:)`` for an event that isn't
    ///   `Encodable`; ``PropertyReadingError/unrepresentableValue(event:property:)`` for a value
    ///   JSON can't hold, or an event whose `encode(to:)` throws.
    package func properties(types: [String: WrittenType?], writingSensitiveValues: Bool) throws(PropertyReadingError) -> [String: JSON] {
        guard let event = event as? any Encodable else {
            throw .notEncodable(name: name)
        }
        let bytes: [UInt8]
        do {
            // Written as a store writes them only when sensitive values are; otherwise each is
            // written as null, which the reader leaves out.
            bytes = try SensitiveCoding.$revealsValues.withValue(writingSensitiveValues) {
                try CBOREncoder().encode(event)
            }
        } catch {
            throw .unrepresentableValue(event: name, property: "")
        }
        return try PropertyReader(redactsSensitiveValues: !writingSensitiveValues).properties(of: bytes, types: types, event: name)
    }
}
