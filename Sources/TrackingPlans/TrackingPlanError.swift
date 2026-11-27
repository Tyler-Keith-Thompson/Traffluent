/// Why schemas can't make a tracking plan.
public enum TrackingPlanError: Error, Sendable, Hashable {
    /// A schema has an empty name, which names no file.
    case emptyEventName
    /// A schema lists two properties with the same name, which one JSON object can't hold.
    case duplicateProperty
    /// Two schemas would be written to the same file: they share a name and a version, or their
    /// names differ only in the case of their letters, which a case-insensitive file system
    /// doesn't tell apart. It carries the name and version of the schema that clashed, and the
    /// fully qualified names (`String(reflecting:)`) of the two event types, in the plan's order,
    /// when the plan knows them: ``TrackingPlan/init()`` does, and ``TrackingPlan/init(schemas:)``,
    /// given schemas alone, gives `nil`. Rename one of the events, or list the schemas by hand.
    case duplicateEvent(String, version: Int, firstType: String?, secondType: String?)
    /// A property's keyword states no rule a JSON Schema can: a negative length or count of
    /// elements, a bound that is NaN or infinite, or a pattern that isn't a valid regular
    /// expression or doesn't match its example.
    case invalidKeyword
}
