/// The shape of an event type: its name, its schema version, its consent category and its stored
/// properties in declaration order, as a value tooling reads.
///
/// The `@Event` macro (module `EventMacros`) writes an event's schema from its declaration, so the
/// two can't drift:
///
/// ```swift
/// @Event(version: 2)
/// struct SignedUp {
///     var plan: String
///     var referrer: String?
/// }
///
/// SignedUp.schema.properties.map(\.name)  // ["plan", "referrer"]
/// ```
public struct EventSchema: Sendable, Hashable {
    /// One stored property of an event: its name, its type as written, whether it is optional,
    /// whether it has a default value and the keywords its value satisfies.
    public struct Property: Sendable, Hashable {
        /// The property's name.
        public var name: String
        /// The property's type as written in source, without the optional: `String` for both
        /// `String` and `String?`.
        public var typeName: String
        /// Whether the property is optional, written `T?`, `T!` or `Optional<T>`.
        public var isOptional: Bool
        /// Whether the property's declaration gives it an initial value, which a stored record
        /// written before the property was added reads as.
        public var hasDefaultValue: Bool
        /// The validation keywords the property's value satisfies, when it has one: its
        /// ``Refined`` type's rule's, then those declared beside it, in order.
        public var keywords: [ValidationKeyword]
        /// Whether the property's type has a rule whose constraints throw as they are built, so
        /// ``keywords`` can't state it and no value of the type can be made. A tracking plan
        /// refuses such a property rather than export it as unconstrained.
        public var hasInvalidConstraint: Bool

        /// The property `name` of type `typeName`, optional when `isOptional` is set, with a
        /// default value when `hasDefaultValue` is set, whose value satisfies `keywords`.
        ///
        /// - Parameters:
        ///   - name: The property's name.
        ///   - typeName: The property's type as written, without the optional.
        ///   - isOptional: Whether the property is optional.
        ///   - hasDefaultValue: Whether the declaration gives the property an initial value; `false`
        ///     by default.
        ///   - hasInvalidConstraint: Whether the type's rule has a constraint that throws as it is
        ///     built; `false` by default.
        ///   - keywords: The keywords the property's value satisfies; none by default.
        public init(name: String, typeName: String, isOptional: Bool, hasDefaultValue: Bool = false, hasInvalidConstraint: Bool = false, keywords: [ValidationKeyword] = []) {
            self.name = name
            self.typeName = typeName
            self.isOptional = isOptional
            self.hasDefaultValue = hasDefaultValue
            self.hasInvalidConstraint = hasInvalidConstraint
            self.keywords = keywords
        }
    }

    /// The name the event is recorded under, its `Event.name`.
    public var name: String
    /// The version of the event's shape, its `Event.schemaVersion`, which its author raises for a
    /// change records stored at the earlier version can't be read through.
    public var version: Int
    /// The purpose the event is collected for, its `Event.consentCategory`.
    public var consentCategory: ConsentCategory
    /// The event's stored properties, in declaration order.
    public var properties: [Property]

    /// The schema of the event named `name`, at `version`, collected for `consentCategory`, with
    /// `properties`.
    ///
    /// - Parameters:
    ///   - name: The name the event is recorded under.
    ///   - version: The version of the event's shape.
    ///   - consentCategory: The purpose the event is collected for.
    ///   - properties: The event's stored properties, in declaration order.
    public init(name: String, version: Int, consentCategory: ConsentCategory, properties: [Property]) {
        self.name = name
        self.version = version
        self.consentCategory = consentCategory
        self.properties = properties
    }
}
