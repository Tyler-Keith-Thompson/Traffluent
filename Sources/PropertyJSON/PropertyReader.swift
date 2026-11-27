public import Events
public import TrackingPlans

/// Reads each record's event properties as JSON, through its event's schema in a tracking plan.
///
/// A JSON batch encoder makes one with the plan it is given and reads every record through it:
///
/// ```swift
/// let reader = PropertyReader(plan: plan)
/// let properties = try reader.properties(of: record, includingSensitiveValues: false)
/// ```
///
/// Each property is read from the event's `Encodable` form, which `@Event` derives, under its
/// name: a `String` is a string; a `Bool` a boolean; an integer, a `Double` or a `Float` a
/// number; a `Date` an ISO 8601 string (`Date.iso8601Timestamp`); a `UUID` an
/// uppercase UUID string; an array an array; and an optional's `nil` is `null`. A `Refined` value
/// is its value. A type the plan can't map is written as its encoding holds it, an object for a
/// struct of the app's own.
///
/// A `Sensitive` value is written only when the reader is asked to include sensitive values and
/// the record reveals them; otherwise the property is left out, an element of an array is
/// `null`, and one inside a type the plan can't map is `null`.
public struct PropertyReader: Sendable {
    // A dictionary of each event version's property types, parsed once here rather than per
    // record: every record of a batch is looked up in it.
    private let propertyTypes: [EventVersion: [String: WrittenType?]]

    /// A reader of the events `plan` describes.
    ///
    /// - Parameter plan: The tracking plan of every event the reader is given: each record's
    ///   event is read through the schema of its name and `Event/schemaVersion` here.
    /// - Complexity: O(*p*) in the plan's properties, which are parsed once here.
    public init(plan: TrackingPlan) {
        var propertyTypes: [EventVersion: [String: WrittenType?]] = [:]
        for schema in plan.schemas {
            propertyTypes[EventVersion(name: schema.name, version: schema.version)] = schema.propertyTypes
        }
        self.propertyTypes = propertyTypes
    }

    /// The properties of `record`'s event, by name.
    ///
    /// - Parameters:
    ///   - record: The record whose event is read.
    ///   - includingSensitiveValues: Whether a `Sensitive` value the record reveals
    ///     (`EventRecord/revealsSensitiveValues`) is written. When `false`, none is, whatever the
    ///     record reveals.
    /// - Returns: Each property's value as JSON.
    /// - Throws: ``PropertyReadingError/unknownEvent(name:version:)`` when the plan has no schema
    ///   of the event at its version; ``PropertyReadingError/notEncodable(name:)`` for an event
    ///   that isn't `Encodable`; ``PropertyReadingError/unrepresentableValue(event:property:)``
    ///   for a value JSON can't hold, or an event whose `encode(to:)` throws.
    /// - Complexity: O(*n* log *n*) in the event's properties.
    public func properties(of record: EventRecord, includingSensitiveValues: Bool) throws(PropertyReadingError) -> [String: JSON] {
        let version = EventVersion(name: record.name, version: type(of: record.event).schemaVersion)
        guard let types = propertyTypes[version] else {
            throw .unknownEvent(name: version.name, version: version.version)
        }
        return try record.properties(types: types, writingSensitiveValues: includingSensitiveValues && record.revealsSensitiveValues)
    }
}

/// An event's name and schema version: what a record's event is looked up in the plan by.
private struct EventVersion: Hashable {
    let name: String
    let version: Int
}
