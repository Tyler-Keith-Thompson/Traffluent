internal import CBOR
package import Events
package import JSONValues
package import TrackingPlans

extension Event where Self: Decodable {
    /// The event whose properties, read as JSON through `types`, are `properties`: the inverse of
    /// `EventRecord`'s `properties(types:writingSensitiveValues:)` with sensitive values written.
    ///
    /// The properties are written back as the CBOR the event's `Decodable` conformance reads, as
    /// a store's record holds it, and read with its `Sensitive` values revealed.
    ///
    /// - Parameters:
    ///   - properties: The event's properties, by name.
    ///   - types: Each property's type as its schema writes it (`EventSchema/propertyTypes`).
    /// - Throws: ``UndecodableProperty`` naming the property that doesn't hold what its type is
    ///   written as, or that the conformance can't read.
    package init(properties: [String: JSON], types: [String: WrittenType?]) throws(UndecodableProperty) {
        let bytes = try CBORPropertyWriter().map(of: properties, types: types).encode()
        do {
            self = try SensitiveCoding.$revealsValues.withValue(true) {
                try CBORDecoder().decode(Self.self, from: bytes)
            }
        } catch let error as DecodingError {
            throw UndecodableProperty(property: error.property)
        } catch {
            throw UndecodableProperty(property: "")
        }
    }
}

extension DecodingError {
    /// The name of the event's property the error is in, the first key of its path; empty when
    /// it is the event's own.
    fileprivate var property: String {
        switch self {
        case .keyNotFound(let key, let context):
            (context.codingPath.first ?? key).stringValue
        case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context):
            context.codingPath.first?.stringValue ?? ""
        @unknown default:
            ""
        }
    }
}
