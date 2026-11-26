import SwiftDiagnostics
import SwiftSyntax

/// One keyword `@Constrained` declares on a property, read from its source: what the expansion
/// copies, and what the macro checks before it does.
struct DeclaredConstraint {
    /// The keyword with its value, as the macro checks it.
    enum Keyword {
        case minLength(Int)
        case maxLength(Int)
        case pattern(String, example: String)
        case minimum(Double)
        case maximum(Double)
        case minItems(Int)
        case maxItems(Int)
    }

    let keyword: Keyword
    /// The argument as written, `.minLength(1)`, which the expansion copies into a typed context
    /// (`[Events.Constraint<String>]`) so the compiler checks it applies to the property's type.
    let expression: ExprSyntax

    var source: String {
        expression.trimmedDescription
    }

    /// The keywords `@Constrained` attributes on `variable` declare, in order, with the
    /// diagnostics of the ones the macro can't use.
    static func constraints(of variable: VariableDeclSyntax) -> (constraints: [DeclaredConstraint], diagnostics: [Diagnostic]) {
        var constraints: [DeclaredConstraint] = []
        var diagnostics: [Diagnostic] = []
        for attribute in variable.attributes {
            guard let attribute = attribute.as(AttributeSyntax.self), attribute.isConstrained,
                case .argumentList(let arguments) = attribute.arguments
            else { continue }
            for argument in arguments {
                switch DeclaredConstraint.parse(argument.expression) {
                case .success(let constraint):
                    constraints.append(constraint)
                case .failure(let diagnostic):
                    diagnostics.append(Diagnostic(node: argument.expression, message: diagnostic))
                }
            }
        }
        if diagnostics.isEmpty {
            diagnostics = conflicts(among: constraints)
        }
        return (constraints, diagnostics)
    }

    private static func parse(_ expression: ExprSyntax) -> Result<DeclaredConstraint, EventMacroDiagnostic> {
        guard let call = expression.as(FunctionCallExprSyntax.self),
            let member = call.calledExpression.as(MemberAccessExprSyntax.self), member.base == nil,
            call.trailingClosure == nil
        else { return .failure(.constraintNotAKeyword) }
        let arguments = Array(call.arguments)
        let name = member.declName.baseName.text
        switch name {
        case "minLength", "maxLength", "minItems", "maxItems":
            guard arguments.count == 1, arguments[0].label == nil,
                let literal = arguments[0].expression.as(IntegerLiteralExprSyntax.self),
                let count = literal.representedLiteralValue
            else { return .failure(.countNotANonNegativeLiteral(keyword: name)) }
            let keyword: Keyword = switch name {
            case "minLength": .minLength(count)
            case "maxLength": .maxLength(count)
            case "minItems": .minItems(count)
            default: .maxItems(count)
            }
            return .success(DeclaredConstraint(keyword: keyword, expression: expression))
        case "minimum", "maximum":
            guard arguments.count == 1, arguments[0].label == nil, let bound = arguments[0].expression.numberLiteralValue else {
                return .failure(.boundNotANumberLiteral(keyword: name))
            }
            return .success(DeclaredConstraint(keyword: name == "minimum" ? .minimum(bound) : .maximum(bound), expression: expression))
        case "pattern":
            guard arguments.count == 2, arguments[0].label == nil, arguments[1].label?.text == "example",
                let pattern = arguments[0].expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue,
                let example = arguments[1].expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue
            else { return .failure(.patternNotALiteral) }
            guard (try? Regex(pattern)) != nil else { return .failure(.invalidPattern(pattern: pattern)) }
            return .success(DeclaredConstraint(keyword: .pattern(pattern, example: example), expression: expression))
        default:
            return .failure(.constraintNotAKeyword)
        }
    }

    /// The errors of constraints no value can satisfy together, each at the later of the two: a
    /// lower bound above an upper one, and a pattern's example another keyword rejects.
    private static func conflicts(among constraints: [DeclaredConstraint]) -> [Diagnostic] {
        var diagnostics: [Diagnostic] = []
        for (index, constraint) in constraints.enumerated() {
            for earlier in constraints[..<index] {
                guard let lower = earlier.keyword.lowerBound(pairedWith: constraint.keyword) ?? constraint.keyword.lowerBound(pairedWith: earlier.keyword),
                    let upper = earlier.keyword.upperBound(pairedWith: constraint.keyword) ?? constraint.keyword.upperBound(pairedWith: earlier.keyword),
                    lower > upper
                else { continue }
                diagnostics.append(Diagnostic(node: constraint.expression, message: EventMacroDiagnostic.unsatisfiable(lower: earlier.source, upper: constraint.source)))
            }
            guard case .pattern(_, let example) = constraint.keyword else { continue }
            if let broken = constraints.first(where: { !$0.keyword.accepts(example) }) {
                diagnostics.append(Diagnostic(node: constraint.expression, message: EventMacroDiagnostic.exampleBreaksKeyword(example: example, keyword: broken.source)))
            }
        }
        return diagnostics
    }
}

extension DeclaredConstraint.Keyword {
    /// This keyword's bound, when it is the lower bound of a pair with `other`, the matching
    /// upper bound: minLength with maxLength, minimum with maximum, minItems with maxItems.
    fileprivate func lowerBound(pairedWith other: Self) -> Double? {
        switch (self, other) {
        case (.minLength(let lower), .maxLength): Double(lower)
        case (.minimum(let lower), .maximum): lower
        case (.minItems(let lower), .maxItems): Double(lower)
        default: nil
        }
    }

    /// This keyword's bound, when it is the upper bound of a pair with `other`, the matching
    /// lower bound.
    fileprivate func upperBound(pairedWith other: Self) -> Double? {
        switch (self, other) {
        case (.maxLength(let upper), .minLength): Double(upper)
        case (.maximum(let upper), .minimum): upper
        case (.maxItems(let upper), .minItems): Double(upper)
        default: nil
        }
    }

    /// Whether a string keyword accepts `string`; `true` for the keywords of other types.
    fileprivate func accepts(_ string: String) -> Bool {
        switch self {
        case .minLength(let length): string.unicodeScalars.count >= length
        case .maxLength(let length): string.unicodeScalars.count <= length
        case .pattern(let pattern, _): (try? Regex(pattern)).map { string.contains($0) } ?? false
        case .minimum, .maximum, .minItems, .maxItems: true
        }
    }
}

extension DeclaredConstraint {
    /// The error of a bound a property of type `typeName` can't state as written, so building
    /// the constraint would throw or a schema would state another bound: an integer bound past
    /// what a `Double` holds exactly, for an integer type, and one that overflows to infinity, or
    /// rounds to another value, for `Float` or `Double`. `nil` for any other keyword or type,
    /// whose constraint is checked as it is built.
    func boundDiagnostic(forType typeName: String) -> EventMacroDiagnostic? {
        switch keyword {
        case .minimum, .maximum: break
        case .minLength, .maxLength, .pattern, .minItems, .maxItems: return nil
        }
        guard let call = expression.as(FunctionCallExprSyntax.self), let argument = call.arguments.first,
            let literal = argument.expression.numberLiteral
        else { return nil }
        switch typeName {
        case "Int", "Int8", "Int16", "Int32", "Int64", "UInt", "UInt8", "UInt16", "UInt32", "UInt64":
            // A Double holds every integer up to 2^53 exactly, and some past it; this asks of
            // the literal's own digits, which no Double has rounded yet.
            guard literal.isInteger, let magnitude = UInt64(literal.digits) else { return nil }
            return Double(exactly: magnitude) == nil ? .inexactBound(keyword: source, type: typeName) : nil
        case "Double", "Float64":
            guard let value = Double(literal.digits), !value.isFinite else { return nil }
            return .boundOverflows(keyword: source, type: typeName)
        case "Float", "Float32":
            guard let value = Float(literal.digits), let written = Double(literal.digits) else { return nil }
            guard value.isFinite else { return .boundOverflows(keyword: source, type: typeName) }
            // A Float bound is stated as its description, as a Float property's value is sent:
            // 0.1, not the 0.10000000149011612 it widens to.
            guard Double(value.description) == written else {
                return .boundRounds(keyword: source, type: typeName, rounded: (literal.isNegative ? "-" : "") + value.description)
            }
            return nil
        default:
            return nil
        }
    }
}

extension AttributeSyntax {
    /// Whether the attribute is `@Constrained`, alone or qualified by its module.
    var isConstrained: Bool {
        let name = attributeName.trimmedDescription
        return name == "Constrained" || name == "EventMacros.Constrained"
    }
}

/// A number literal as written: its digits without underscores, whether a `-` led it, and
/// whether it is an integer literal.
struct NumberLiteral {
    let digits: String
    let isNegative: Bool
    let isInteger: Bool
}

extension ExprSyntax {
    /// The literal, if the expression is an integer or floating-point literal, with or without a
    /// leading `-`.
    fileprivate var numberLiteral: NumberLiteral? {
        if let prefix = self.as(PrefixOperatorExprSyntax.self), prefix.operator.text == "-" {
            return prefix.expression.numberLiteral.map { NumberLiteral(digits: $0.digits, isNegative: !$0.isNegative, isInteger: $0.isInteger) }
        }
        if let integer = self.as(IntegerLiteralExprSyntax.self) {
            return NumberLiteral(digits: integer.literal.text.filter { $0 != "_" }, isNegative: false, isInteger: true)
        }
        if let float = self.as(FloatLiteralExprSyntax.self) {
            return NumberLiteral(digits: float.literal.text.filter { $0 != "_" }, isNegative: false, isInteger: false)
        }
        return nil
    }

    /// The value of an integer or floating-point literal, negated by a leading `-`; `nil` for any
    /// other expression.
    fileprivate var numberLiteralValue: Double? {
        if let prefix = self.as(PrefixOperatorExprSyntax.self), prefix.operator.text == "-" {
            return prefix.expression.numberLiteralValue.map { -$0 }
        }
        let text: String
        if let integer = self.as(IntegerLiteralExprSyntax.self) {
            text = integer.literal.text
        } else if let float = self.as(FloatLiteralExprSyntax.self) {
            text = float.literal.text
        } else {
            return nil
        }
        return Double(text.filter { $0 != "_" })
    }
}
