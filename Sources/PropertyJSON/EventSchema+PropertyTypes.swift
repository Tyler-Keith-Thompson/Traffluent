package import Events
package import TrackingPlans

extension EventSchema {
    /// Each property's type as written, optional when the property is; `nil` for a type the plan
    /// can't parse, whose value is written as its encoding holds it.
    package var propertyTypes: [String: WrittenType?] {
        // Unique: TrackingPlan rejects a schema with two properties of one name. Were two to share
        // one all the same, the first is the one read.
        Dictionary(properties.map { property in
            let type = WrittenType(parsing: property.typeName)
            return (property.name, property.isOptional ? type.map(WrittenType.optional) : type)
        }) { first, _ in first }
    }
}
