/// The rule a ``Refined`` value satisfies: the constraints on its value, which a type lists once
/// and names in every property that keeps it.
///
/// ```swift
/// enum CouponCode: Refinement {
///     static let constraints: [Constraint<String>] = [
///         .pattern("^[A-Z0-9]{6}$", example: "SPRING"),
///     ]
/// }
///
/// let coupon = Refined<String, CouponCode>("SPRING")
/// ```
///
/// Declare ``constraints`` with `static let`, so they are built once rather than on every value
/// made.
public protocol Refinement {
    /// The type of the values the rule constrains.
    associatedtype Value: Sendable

    /// What every value satisfies, checked in order.
    static var constraints: [Constraint<Value>] { get }
}
