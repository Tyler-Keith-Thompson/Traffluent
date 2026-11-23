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
    /// One stored property of an event: its name, its type as written and whether it is optional.
    public struct Property: Sendable, Hashable {
        /// The property's name.
        public var name: String
        /// The property's type as written in source, without the optional: `String` for both
        /// `String` and `String?`.
        public var typeName: String
        /// Whether the property is optional, written `T?`, `T!` or `Optional<T>`.
        public var isOptional: Bool

        /// The property `name` of type `typeName`, optional when `isOptional` is set.
        ///
        /// - Parameters:
        ///   - name: The property's name.
        ///   - typeName: The property's type as written, without the optional.
        ///   - isOptional: Whether the property is optional.
        public init(name: String, typeName: String, isOptional: Bool) {
            self.name = name
            self.typeName = typeName
            self.isOptional = isOptional
        }
    }

    /// The name the event is recorded under, its `Event.name`.
    public var name: String
    /// The version of the event's shape, which its author raises when the properties change.
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
