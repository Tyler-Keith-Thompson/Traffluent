/// Something that happened, recorded as a typed value.
///
/// An event is a value type whose stored properties are its properties, so a misspelled or
/// mistyped property is a compile error rather than a bad row in a destination.
///
/// ```swift
/// struct SignedUp: Event {
///     var plan: String
/// }
/// ```
public protocol Event: Sendable {
    /// The name destinations record the event under. Defaults to the type's name.
    static var name: String { get }
}

extension Event {
    /// The type's name, as written in source.
    public static var name: String { String(describing: Self.self) }
}
