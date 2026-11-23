/// A value that satisfies every constraint of `Rule`, checked once as it is made, so a property of
/// this type can't hold one that doesn't.
///
/// ```swift
/// enum PlanName: Refinement {
///     static let constraints: [Constraint<String>] = [.minLength(1), .maxLength(32)]
/// }
///
/// struct SignedUp: Event {
///     var plan: Refined<String, PlanName>
/// }
///
/// let plan = try Refined<String, PlanName>(checked: "")  // throws UnsatisfiedConstraint.minLength
/// ```
///
/// The plain initializer traps on a value that breaks a constraint, as an `Array` subscript does
/// out of range; ``init(checked:)`` throws instead. An event's schema lists the rule's keywords
/// for the property, and a tracking plan exports them. Decoding a stored value that no longer
/// satisfies the rule fails rather than make one.
public struct Refined<Value: Sendable, Rule: Refinement>: Sendable where Rule.Value == Value {
    /// The value, which satisfies every one of `Rule`'s constraints.
    public let value: Value

    /// `value`, refined by `Rule`.
    ///
    /// - Parameter value: The value.
    /// - Precondition: `value` satisfies every one of `Rule`'s constraints.
    public init(_ value: Value) {
        if let broken = Rule.constraints.first(where: { !$0.isSatisfied(by: value) }) {
            // The value isn't printed: it may be a sensitive one.
            preconditionFailure("Refined<\(Value.self), \(Rule.self)>: the value breaks \(broken.keyword)")
        }
        self.value = value
    }

    /// `value`, refined by `Rule`, or an error naming the first constraint it breaks.
    ///
    /// - Parameter value: The value.
    /// - Throws: ``UnsatisfiedConstraint``, the keyword of the first of `Rule`'s constraints, in
    ///   order, that `value` breaks.
    public init(checked value: Value) throws(UnsatisfiedConstraint) {
        if let broken = Rule.constraints.first(where: { !$0.isSatisfied(by: value) }) {
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
        Rule.constraints.map(\.keyword)
    }
}
