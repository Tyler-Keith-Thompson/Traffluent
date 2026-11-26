/// A property of an event whose value breaks one of the constraints declared on it, or one of
/// whose constraints couldn't be built: the property's name and the cause.
///
/// An event returns the first it finds from ``Event/constraintViolation()``, and a tracker rejects
/// the event, reporting it.
public struct ConstraintViolation: Sendable, Hashable, CustomStringConvertible {
    /// Why a property's value is rejected.
    public enum Cause: Sendable, Hashable {
        /// The value breaks the keyword.
        case unsatisfied(ValidationKeyword)
        /// The constraint declared as `declaration` (`.maximum(9_007_199_254_740_993)`) threw
        /// `error` as it was built, so no value of the property satisfies it.
        case invalidConstraint(declaration: String, error: InvalidConstraint)
    }

    /// The property's name, as the event's schema lists it.
    public var property: String
    /// Why its value is rejected.
    public var cause: Cause

    /// The violation of `keyword` by `property`'s value.
    ///
    /// - Parameters:
    ///   - property: The property's name.
    ///   - keyword: The keyword its value breaks.
    public init(property: String, keyword: ValidationKeyword) {
        self.property = property
        cause = .unsatisfied(keyword)
    }

    /// The violation of a constraint on `property` that couldn't be built.
    ///
    /// - Parameters:
    ///   - property: The property's name.
    ///   - declaration: The constraint as it is declared, such as `.maximum(9_007_199_254_740_993)`.
    ///   - error: What building it threw.
    public init(property: String, invalidConstraint declaration: String, error: InvalidConstraint) {
        self.property = property
        cause = .invalidConstraint(declaration: declaration, error: error)
    }

    /// `"<property>" breaks <keyword>`, or `"<property>"'s <declaration> can't be built
    /// (<error>)`.
    public var description: String {
        switch cause {
        case .unsatisfied(let keyword):
            "\"\(property)\" breaks \(keyword)"
        case .invalidConstraint(let declaration, let error):
            "\"\(property)\"'s \(declaration) can't be built (\(error))"
        }
    }
}
