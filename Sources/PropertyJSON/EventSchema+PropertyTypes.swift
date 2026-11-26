package import Events
package import TrackingPlans

extension EventSchema {
    /// Each property's type as written, optional when the property is; `nil` for a type the plan
    /// can't parse, whose value is written as its encoding holds it. An optional property of such
    /// a type is still optional, wrapping a named type spelled as written, so its `nil` is `null`.
    package var propertyTypes: [String: WrittenType?] {
        // Unique: TrackingPlan rejects a schema with two properties of one name. Were two to share
        // one all the same, the first is the one read.
        Dictionary(properties.map { property in
            let type = WrittenType(parsing: property.typeName)
            guard property.isOptional else { return (property.name, type) }
            // A type the grammar doesn't cover ([String: Int], a tuple) as one name, which no
            // shape matches, so its value is read for what it holds, as a nil type's is.
            return (property.name, .optional(type ?? .named([property.typeName], [])))
        }) { first, _ in first }
    }
}
