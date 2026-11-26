/// The constraint a value broke, by its keyword: thrown by ``Refined/init(_:)``.
///
/// One case per ``ValidationKeyword``, without its value, and one for a rule whose constraints
/// can't be built, so a single `catch` handles every way a value can fail to be refined.
public enum UnsatisfiedConstraint: Error, Sendable, Hashable {
    /// A string is shorter than its ``ValidationKeyword/minLength(_:)``.
    case minLength
    /// A string is longer than its ``ValidationKeyword/maxLength(_:)``.
    case maxLength
    /// A string doesn't match its ``ValidationKeyword/pattern(_:example:)``.
    case pattern
    /// A number is below its ``ValidationKeyword/minimum(_:)``.
    case minimum
    /// A number is above its ``ValidationKeyword/maximum(_:)``.
    case maximum
    /// An array holds fewer elements than its ``ValidationKeyword/minItems(_:)``.
    case minItems
    /// An array holds more elements than its ``ValidationKeyword/maxItems(_:)``.
    case maxItems
    /// The rule's ``Refinement/constraints`` threw ``InvalidConstraint``, so no value satisfies
    /// it.
    case invalidConstraint
}
