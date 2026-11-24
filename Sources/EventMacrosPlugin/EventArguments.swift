import SwiftDiagnostics
import SwiftSyntax

/// What `@Event(name:consent:version:)` was given, as source text the expansion copies.
struct EventArguments {
    /// The name's string literal, or `nil` when the type's name is the event's.
    var name: ExprSyntax?
    /// The consent category's expression, or `nil` when the event keeps `Event`'s default.
    var consent: ExprSyntax?
    /// The schema version, or `nil` when the event keeps `Event`'s default, 1.
    var version: Int?

    /// The arguments of `attribute`, with the diagnostics of the ones the macro can't use.
    static func arguments(of attribute: AttributeSyntax) -> (arguments: EventArguments, diagnostics: [Diagnostic]) {
        var arguments = EventArguments()
        var diagnostics: [Diagnostic] = []
        guard case .argumentList(let list) = attribute.arguments else { return (arguments, diagnostics) }
        for argument in list {
            let expression = argument.expression
            // `nil` asks for the default, as leaving the argument out does.
            if expression.is(NilLiteralExprSyntax.self) { continue }
            switch argument.label?.text {
            case "name":
                if let diagnostic = expression.nameDiagnostic {
                    diagnostics.append(Diagnostic(node: expression, message: diagnostic))
                } else {
                    arguments.name = expression.trimmed
                }
            case "consent":
                arguments.consent = expression.trimmed
            case "version":
                guard let version = expression.as(IntegerLiteralExprSyntax.self)?.representedLiteralValue, version >= 1 else {
                    diagnostics.append(Diagnostic(node: expression, message: EventMacroDiagnostic.versionNotAPositiveLiteral))
                    continue
                }
                arguments.version = version
            default:
                // The compiler checks the arguments against the macro's declaration first.
                continue
            }
        }
        return (arguments, diagnostics)
    }
}

extension ExprSyntax {
    /// Why the expression can't be an event's name, or `nil` when it is a non-empty string literal
    /// without interpolation.
    fileprivate var nameDiagnostic: EventMacroDiagnostic? {
        guard let literal = self.as(StringLiteralExprSyntax.self),
              literal.segments.allSatisfy({ $0.is(StringSegmentSyntax.self) })
        else { return .nameNotALiteral }
        let isEmpty = literal.segments.allSatisfy { $0.as(StringSegmentSyntax.self)?.content.text.isEmpty ?? true }
        return isEmpty ? .emptyName : nil
    }
}
