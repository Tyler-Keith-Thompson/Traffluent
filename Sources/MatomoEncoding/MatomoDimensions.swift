import Events
public import TrackingPlans

/// Which of Matomo's custom dimensions each property of a tracking plan is sent as, by the
/// property's name and the dimension's ID.
///
/// Matomo numbers the custom dimensions of a site as they are made, in its settings (Administration,
/// Websites, Custom Dimensions), and reads a request's `dimension3` as the value of dimension 3, so
/// the mapping comes from the app:
///
/// ```swift
/// let dimensions: MatomoDimensions = ["plan": 1, "seats": 2]
/// ```
///
/// A property is mapped by its name, the same in every event of the plan that has it. A property
/// no mapping names is never sent, and ``unmappedProperties(in:)`` lists those of a plan, which
/// the encoder logs once when it is made.
///
/// A literal doesn't check anything, so it can't fail: the destination's factory checks the
/// mapping against the plan, and throws ``MatomoSetupError`` for a dimension ID below 1, a
/// property mapped twice, a property no event of the plan has, a property that is `Sensitive` in
/// an event, and two properties of one event mapped to one dimension.
// A type of its own rather than [String: Int]: a Dictionary literal with a key written twice traps
// when it is built, and this one's literal keeps both, so the factory throws instead (D10).
public struct MatomoDimensions: Sendable, ExpressibleByDictionaryLiteral {
    /// The mappings in the order they were given, duplicates included, for the factory to refuse.
    let mappings: [Mapping]

    /// The mapping of each property named in `elements` to the dimension beside it.
    ///
    /// - Parameter elements: Each property's name and its dimension's ID.
    public init(dictionaryLiteral elements: (String, Int)...) {
        mappings = elements.map { Mapping(property: $0.0, dimension: $0.1) }
    }

    /// The mapping of each property named in `dimensions` to its value, a dimension's ID.
    ///
    /// - Parameter dimensions: Each property's dimension's ID, by the property's name.
    public init(_ dimensions: [String: Int]) {
        // In the order of the names' UTF-8 bytes, so the factory reports the same error first
        // whatever order the dictionary iterates in.
        mappings = dimensions
            .sorted { $0.key.utf8.lexicographicallyPrecedes($1.key.utf8) }
            .map { Mapping(property: $0.key, dimension: $0.value) }
    }

    /// The properties of `plan`'s events that no mapping names, and that Matomo is never sent.
    ///
    /// `Sensitive` properties are listed too, as Matomo is never sent them and they can't be
    /// mapped. An app that means every other property to reach Matomo checks in a test that this
    /// lists only its `Sensitive` ones.
    ///
    /// - Parameter plan: The tracking plan the destination is made with.
    /// - Returns: Each such property, in the order of the plan's events and of each event's
    ///   properties.
    /// - Complexity: O(*p* + *m*) in the plan's properties and the mappings.
    public func unmappedProperties(in plan: TrackingPlan) -> [MatomoUnmappedProperty] {
        let mapped = Set(mappings.map(\.property))
        return plan.schemas.flatMap { schema in
            schema.properties
                .filter { !mapped.contains($0.name) }
                .map { MatomoUnmappedProperty(event: schema.name, version: schema.version, property: $0.name) }
        }
    }

    /// Each mapped property's dimension, once the mappings keep every rule against `plan`.
    ///
    /// - Throws: ``MatomoSetupError/invalidDimension(property:dimension:)``,
    ///   ``MatomoSetupError/duplicateProperty(_:)``, ``MatomoSetupError/unknownProperty(_:)``,
    ///   ``MatomoSetupError/sensitiveProperty(event:version:property:)`` and
    ///   ``MatomoSetupError/sharedDimension(event:version:dimension:)``, in that order of checks,
    ///   each naming the first in the mappings' order, or the plan's for the last two.
    func dimensions(checkedAgainst plan: TrackingPlan) throws(MatomoSetupError) -> [String: Int] {
        if let invalid = mappings.first(where: { $0.dimension < 1 }) {
            throw .invalidDimension(property: invalid.property, dimension: invalid.dimension)
        }
        var dimensions: [String: Int] = [:]
        for mapping in mappings {
            guard dimensions.updateValue(mapping.dimension, forKey: mapping.property) == nil else {
                throw .duplicateProperty(mapping.property)
            }
        }
        let properties = Set(plan.schemas.flatMap { $0.properties.map(\.name) })
        if let unknown = mappings.first(where: { !properties.contains($0.property) }) {
            throw .unknownProperty(unknown.property)
        }
        for schema in plan.schemas {
            if let sensitive = schema.properties.first(where: { dimensions[$0.name] != nil && $0.isSensitive }) {
                throw .sensitiveProperty(event: schema.name, version: schema.version, property: sensitive.name)
            }
        }
        for schema in plan.schemas {
            var used: Set<Int> = []
            for property in schema.properties {
                guard let dimension = dimensions[property.name] else { continue }
                guard used.insert(dimension).inserted else {
                    throw .sharedDimension(event: schema.name, version: schema.version, dimension: dimension)
                }
            }
        }
        return dimensions
    }
}

extension EventSchema.Property {
    /// Whether the property's type is `Sensitive`, or an optional or array of it, which the
    /// property reader never sends.
    // Read with the plan's own parser of a type's text, as its JSON Schema export marks a
    // sensitive property, rather than matching the text: `Events.Sensitive<String>?` and
    // `[Sensitive<String>]` are sensitive too, and an app's type named `MySensitive` isn't.
    fileprivate var isSensitive: Bool {
        WrittenType(parsing: typeName)?.holdsSensitive ?? false
    }
}

extension WrittenType {
    fileprivate var holdsSensitive: Bool {
        switch self {
        case .optional(let wrapped), .array(let wrapped):
            return wrapped.holdsSensitive
        case .named:
            if names("Sensitive", in: ["Events", "Traffluent"])?.count == 1 {
                return true
            }
            if let arguments = names("Optional", in: ["Swift"]) ?? names("Array", in: ["Swift"]), arguments.count == 1 {
                return arguments[0].holdsSensitive
            }
            return false
        }
    }
}

extension MatomoDimensions {
    /// One property's dimension, as it was given.
    struct Mapping: Sendable {
        let property: String
        let dimension: Int
    }
}
