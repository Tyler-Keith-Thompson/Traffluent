/// Why schemas can't make a tracking plan.
public enum TrackingPlanError: Error, Sendable, Hashable {
    /// A schema has an empty name, which names no file.
    case emptyEventName
    /// A schema lists two properties with the same name, which one JSON object can't hold.
    case duplicateProperty
    /// Two schemas would be written to the same file: they share a name and a version, or their
    /// names differ only in the case of their letters, which a case-insensitive file system
    /// doesn't tell apart.
    case duplicateEvent
    /// A property's keyword states no rule a JSON Schema can: a negative length or count of
    /// elements, a bound that is NaN or infinite, or a pattern that isn't a valid regular
    /// expression or doesn't match its example.
    case invalidKeyword
}
