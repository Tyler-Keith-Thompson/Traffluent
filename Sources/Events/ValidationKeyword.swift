/// A rule a property's value must satisfy, as one of JSON Schema's validation keywords (draft
/// 2020-12): a bound on a string's length, on a number, or on an array's count, or a pattern a
/// string matches.
///
/// A keyword is what an event's schema and a ``ConstraintViolation`` name. Code that checks a value
/// builds a ``Constraint`` instead, whose spellings are the keyword's for the value's type.
///
/// A string's length counts its Unicode scalars, as JSON Schema counts a string's characters.
public enum ValidationKeyword: Sendable, Hashable, CustomStringConvertible {
    /// A string holds at least this many Unicode scalars.
    case minLength(Int)
    /// A string holds at most this many Unicode scalars.
    case maxLength(Int)
    /// A string holds a match of this regular expression, anywhere in it unless the pattern is
    /// anchored with `^` and `$`; `example` is a string that matches, which a tracking plan's
    /// example payload uses.
    case pattern(String, example: String)
    /// A number is at least this.
    case minimum(Double)
    /// A number is at most this.
    case maximum(Double)
    /// An array holds at least this many elements.
    case minItems(Int)
    /// An array holds at most this many elements.
    case maxItems(Int)

    /// The keyword as JSON Schema writes it, with its value: `minLength 1`, `pattern ^[a-z]+$`.
    public var description: String {
        switch self {
        case .minLength(let length): "minLength \(length)"
        case .maxLength(let length): "maxLength \(length)"
        case .pattern(let pattern, _): "pattern \(pattern)"
        case .minimum(let bound): "minimum \(bound.keywordDescription)"
        case .maximum(let bound): "maximum \(bound.keywordDescription)"
        case .minItems(let count): "minItems \(count)"
        case .maxItems(let count): "maxItems \(count)"
        }
    }

    /// The keywords every value of `type` satisfies because the type enforces them as it is made:
    /// a ``Refined`` type's rule's, also through `Optional` and ``Sensitive``; none for any other
    /// type.
    ///
    /// `@Event` reads a property's keywords through this, for its schema.
    ///
    /// - Parameter type: A property's type.
    /// - Returns: Its rule's keywords, in the rule's order.
    public static func keywords(of type: Any.Type) -> [ValidationKeyword] {
        (type as? any RefinedKeywords.Type)?.keywords ?? []
    }

    /// The keywords every value at `keyPath` satisfies because its type enforces them, as
    /// ``keywords(of:)`` reads them.
    ///
    /// - Parameter keyPath: A property of an event.
    /// - Returns: Its type's keywords.
    public static func keywords<Root, Value>(of keyPath: KeyPath<Root, Value>) -> [ValidationKeyword] {
        keywords(of: Value.self)
    }

    /// Whether the type at `keyPath` is a ``Refined`` type, also through `Optional` and
    /// ``Sensitive``, whose rule's constraints throw as they are built, so `keywords(of:)`
    /// gives none and no value of it can be made.
    ///
    /// `@Event` reads this for its schema, whose tracking plan refuses such a property.
    ///
    /// - Parameter keyPath: A property of an event.
    /// - Returns: Whether its type's rule throws.
    public static func hasInvalidConstraint<Root, Value>(of keyPath: KeyPath<Root, Value>) -> Bool {
        (Value.self as? any RefinedKeywords.Type)?.hasInvalidConstraint ?? false
    }

    /// The keyword's case, without its value.
    var unsatisfied: UnsatisfiedConstraint {
        switch self {
        case .minLength: .minLength
        case .maxLength: .maxLength
        case .pattern: .pattern
        case .minimum: .minimum
        case .maximum: .maximum
        case .minItems: .minItems
        case .maxItems: .maxItems
        }
    }
}

/// A type whose values satisfy keywords by construction, so a schema can list them.
///
/// Internal, and found by a dynamic cast in ``ValidationKeyword/keywords(of:)``, so `Optional` and
/// `Sensitive` forward their wrapped type's without a public protocol adopters would see.
protocol RefinedKeywords {
    static var keywords: [ValidationKeyword] { get }
    static var hasInvalidConstraint: Bool { get }
}

extension Optional: RefinedKeywords where Wrapped: RefinedKeywords {
    static var keywords: [ValidationKeyword] {
        Wrapped.keywords
    }

    static var hasInvalidConstraint: Bool {
        Wrapped.hasInvalidConstraint
    }
}

extension Sensitive: RefinedKeywords where Value: RefinedKeywords {
    static var keywords: [ValidationKeyword] {
        Value.keywords
    }

    static var hasInvalidConstraint: Bool {
        Value.hasInvalidConstraint
    }
}

extension Double {
    /// The bound as a keyword shows it: an integer without a fraction, `1` rather than `1.0`.
    fileprivate var keywordDescription: String {
        // 2^53: every integer up to it is exact as a Double, and converts to Int64 exactly.
        if rounded() == self, abs(self) <= 9_007_199_254_740_992 {
            return String(Int64(self))
        }
        return description
    }
}
