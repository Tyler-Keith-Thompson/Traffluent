/// A rule a value of type `Value` must satisfy: one ``ValidationKeyword``, offered only where it
/// applies to the type, with its bound in the value's own type.
///
/// A string takes ``minLength(_:)``, ``maxLength(_:)`` and ``pattern(_:example:)``; an integer or a
/// floating-point number `minimum(_:)` and `maximum(_:)`; an array ``minItems(_:)`` and
/// ``maxItems(_:)``. Any other spelling for a type is a compile error:
///
/// ```swift
/// let constraints: [Constraint<String>] = [.minLength(1), .maxLength(64)]
/// constraints.allSatisfy { $0.isSatisfied(by: "pro") }  // true
/// ```
///
/// A ``Refinement`` lists the constraints a ``Refined`` value satisfies; `@Constrained` (module
/// `EventMacros`) declares them beside an event's property.
public struct Constraint<Value: Sendable>: Sendable {
    /// The keyword the constraint checks, as a schema writes it.
    public let keyword: ValidationKeyword
    private let check: @Sendable (Value) -> Bool

    private init(_ keyword: ValidationKeyword, check: @escaping @Sendable (Value) -> Bool) {
        self.keyword = keyword
        self.check = check
    }

    /// Whether `value` satisfies the constraint.
    ///
    /// - Parameter value: The value to check.
    /// - Returns: `true` when it does.
    /// - Complexity: O(*n*) in a string's length for a length, and in its length times the
    ///   pattern's for a pattern, which is compiled on every call; O(1) otherwise.
    public func isSatisfied(by value: Value) -> Bool {
        check(value)
    }
}

extension Constraint: Equatable, Hashable {
    /// Whether the two check the same keyword.
    public static func == (lhs: Constraint, rhs: Constraint) -> Bool {
        lhs.keyword == rhs.keyword
    }

    /// Hashes the keyword.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(keyword)
    }
}

extension Constraint where Value == String {
    /// A string holds at least `length` Unicode scalars: ``ValidationKeyword/minLength(_:)``.
    ///
    /// - Parameter length: The fewest scalars.
    /// - Precondition: `length` is not negative.
    public static func minLength(_ length: Int) -> Constraint {
        precondition(length >= 0, "minLength can't be negative, not \(length)")
        return Constraint(.minLength(length)) { $0.unicodeScalars.count >= length }
    }

    /// A string holds at most `length` Unicode scalars: ``ValidationKeyword/maxLength(_:)``.
    ///
    /// - Parameter length: The most scalars.
    /// - Precondition: `length` is not negative.
    public static func maxLength(_ length: Int) -> Constraint {
        precondition(length >= 0, "maxLength can't be negative, not \(length)")
        return Constraint(.maxLength(length)) { $0.unicodeScalars.count <= length }
    }

    /// A string holds a match of the regular expression `pattern`: ``ValidationKeyword/pattern(_:example:)``.
    ///
    /// The pattern is a Swift `Regex`, matched anywhere in the string as JSON Schema's `pattern`
    /// is; anchor it with `^` and `$` to match the whole string. Keep to the syntax Swift's and
    /// ECMA-262's regular expressions share (literals, classes, `\d`, groups, alternation,
    /// quantifiers, anchors), so a plan's other readers match it the same way.
    ///
    /// - Parameters:
    ///   - pattern: The regular expression.
    ///   - example: A string the pattern matches, for a tracking plan's example payload.
    /// - Precondition: `pattern` is a valid regular expression, and `example` matches it.
    public static func pattern(_ pattern: String, example: String) -> Constraint {
        // A trap rather than an error: a pattern is written in source, and one that doesn't
        // compile is a programming mistake no caller could handle.
        guard let regex = try? Regex(pattern) else {
            preconditionFailure("The pattern \(pattern) isn't a valid regular expression")
        }
        precondition(example.contains(regex), "The pattern \(pattern) doesn't match its example \(example)")
        // Compiled again on every check: Regex isn't Sendable, so the closure can't keep it, and a
        // shared cache would be global mutable state. A check runs on a tracker's worker, never on
        // the caller, so the microseconds it costs block no one.
        return Constraint(.pattern(pattern, example: example)) { value in
            guard let regex = try? Regex(pattern) else { return false }
            return value.contains(regex)
        }
    }
}

extension Constraint where Value: BinaryInteger {
    /// An integer is at least `bound`: ``ValidationKeyword/minimum(_:)``.
    ///
    /// - Parameter bound: The smallest value.
    public static func minimum(_ bound: Value) -> Constraint {
        Constraint(.minimum(Double(bound))) { $0 >= bound }
    }

    /// An integer is at most `bound`: ``ValidationKeyword/maximum(_:)``.
    ///
    /// - Parameter bound: The largest value.
    public static func maximum(_ bound: Value) -> Constraint {
        Constraint(.maximum(Double(bound))) { $0 <= bound }
    }
}

extension Constraint where Value: BinaryFloatingPoint {
    /// A number is at least `bound`: ``ValidationKeyword/minimum(_:)``. NaN satisfies no bound.
    ///
    /// - Parameter bound: The smallest value.
    /// - Precondition: `bound` is finite, as a JSON number is.
    public static func minimum(_ bound: Value) -> Constraint {
        precondition(bound.isFinite, "minimum must be finite, not \(bound)")
        return Constraint(.minimum(Double(bound))) { $0 >= bound }
    }

    /// A number is at most `bound`: ``ValidationKeyword/maximum(_:)``. NaN satisfies no bound.
    ///
    /// - Parameter bound: The largest value.
    /// - Precondition: `bound` is finite, as a JSON number is.
    public static func maximum(_ bound: Value) -> Constraint {
        precondition(bound.isFinite, "maximum must be finite, not \(bound)")
        return Constraint(.maximum(Double(bound))) { $0 <= bound }
    }
}

extension Constraint {
    /// An array holds at least `count` elements: ``ValidationKeyword/minItems(_:)``.
    ///
    /// - Parameter count: The fewest elements.
    /// - Precondition: `count` is not negative.
    public static func minItems<Element>(_ count: Int) -> Constraint where Value == [Element] {
        precondition(count >= 0, "minItems can't be negative, not \(count)")
        return Constraint(.minItems(count)) { $0.count >= count }
    }

    /// An array holds at most `count` elements: ``ValidationKeyword/maxItems(_:)``.
    ///
    /// - Parameter count: The most elements.
    /// - Precondition: `count` is not negative.
    public static func maxItems<Element>(_ count: Int) -> Constraint where Value == [Element] {
        precondition(count >= 0, "maxItems can't be negative, not \(count)")
        return Constraint(.maxItems(count)) { $0.count <= count }
    }
}
