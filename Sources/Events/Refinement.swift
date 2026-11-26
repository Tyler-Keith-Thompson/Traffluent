/// The rule a ``Refined`` value satisfies: the constraints on its value, which a type lists once
/// and names in every property that keeps it.
///
/// ```swift
/// enum CouponCode: Refinement {
///     static var constraints: [Constraint<String>] {
///         get throws(InvalidConstraint) { try [.pattern("^[A-Z0-9]{6}$", example: "SPRING")] }
///     }
/// }
///
/// let coupon = try Refined<String, CouponCode>("SPRING")
/// ```
///
/// Every ``Constraint`` spelling throws ``InvalidConstraint`` for an argument no schema can hold,
/// so ``constraints`` is read with `try`, each time a value is refined.
public protocol Refinement {
    /// The type of the values the rule constrains.
    associatedtype Value: Sendable

    /// What every value satisfies, checked in order.
    ///
    /// - Throws: ``InvalidConstraint`` when a constraint's argument is invalid, which leaves the
    ///   rule with no value that satisfies it.
    static var constraints: [Constraint<Value>] { get throws(InvalidConstraint) }
}
