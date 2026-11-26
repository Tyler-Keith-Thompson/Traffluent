/// The error a ``Constraint`` spelling throws for an argument no schema can hold.
///
/// One case per rule the spellings check, without the argument, so a single `catch` handles every
/// constraint a list can build.
public enum InvalidConstraint: Error, Sendable, Hashable {
    /// A length or a count of elements below 0: ``Constraint/minLength(_:)``,
    /// ``Constraint/maxLength(_:)``, ``Constraint/minItems(_:)`` or ``Constraint/maxItems(_:)``.
    case negativeCount
    /// A floating-point bound that is NaN or infinite, which a JSON number can't be.
    case nonFiniteBound
    /// An integer bound a `Double` can't hold exactly, such as an `Int64` past 2⁵³, so a schema
    /// would state another bound than the one checked.
    case inexactBound
    /// A pattern that isn't a valid regular expression.
    case invalidPattern
    /// A pattern that doesn't match its example.
    case exampleMismatch
}
