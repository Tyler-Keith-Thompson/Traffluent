/// A value that satisfies every constraint of `Rule`, checked once as it is made, so a property of
/// this type can't hold one that doesn't.
///
/// ```swift
/// enum PlanName: Refinement {
///     static var constraints: [Constraint<String>] {
///         get throws(InvalidConstraint) { try [.minLength(1), .maxLength(32)] }
///     }
/// }
///
/// struct SignedUp: Event {
///     var plan: Refined<String, PlanName>
/// }
///
/// let plan = try Refined<String, PlanName>("")  // throws UnsatisfiedConstraint.minLength
/// ```
///
/// The initializer throws for a value that breaks a constraint. An event's schema lists the
/// rule's keywords for the property, and a tracking plan exports them. Decoding a stored value
/// that no longer satisfies the rule fails rather than make one.
public struct Refined<Value: Sendable, Rule: Refinement>: Sendable where Rule.Value == Value {
    /// The value, which satisfies every one of `Rule`'s constraints.
    public let value: Value

    /// `value`, refined by `Rule`, or an error naming the first constraint it breaks.
    ///
    /// - Parameter value: The value.
    /// - Throws: ``UnsatisfiedConstraint``, the keyword of the first of `Rule`'s constraints, in
    ///   order, that `value` breaks, or ``UnsatisfiedConstraint/invalidConstraint`` when `Rule`'s
    ///   constraints throw ``InvalidConstraint``, so no value satisfies them.
    public init(_ value: Value) throws(UnsatisfiedConstraint) {
        let constraints: [Constraint<Value>]
        do {
            constraints = try Rule.constraints
        } catch {
            throw .invalidConstraint
        }
        if let broken = constraints.first(where: { !$0.isSatisfied(by: value) }) {
            throw broken.keyword.unsatisfied
        }
        self.value = value
    }
}

extension Refined: Equatable where Value: Equatable {}

extension Refined: Hashable where Value: Hashable {}

extension Refined: Comparable where Value: Comparable {
    /// Whether `lhs`'s value orders before `rhs`'s.
    public static func < (lhs: Refined, rhs: Refined) -> Bool {
        lhs.value < rhs.value
    }
}

extension Refined: CustomStringConvertible {
    /// The value's description.
    public var description: String {
        String(describing: value)
    }
}

extension Refined: RefinedKeywords {
    static var keywords: [ValidationKeyword] {
        // None for a rule whose constraints throw, which hasInvalidConstraint says, so a tracking
        // plan refuses the property rather than export it as unconstrained.
        (try? Rule.constraints.map(\.keyword)) ?? []
    }

    static var hasInvalidConstraint: Bool {
        (try? Rule.constraints) == nil
    }
}
