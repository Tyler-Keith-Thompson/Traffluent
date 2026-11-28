import SwiftSyntax

extension StructDeclSyntax {
    /// The type's name as `String(describing:)` writes it, `Event.name`'s default: without the
    /// backticks of an escaped identifier.
    var typeName: String {
        let text = name.text
        guard text.count >= 2, text.hasPrefix("`"), text.hasSuffix("`") else { return text }
        return String(text.dropFirst().dropLast())
    }

    /// The static `name` property the struct declares itself, if any, whose value the macro can't
    /// read.
    var nameMember: VariableDeclSyntax? {
        memberBlock.members.lazy
            .compactMap { $0.decl.as(VariableDeclSyntax.self) }
            .first { variable in
                variable.modifiers.contains { $0.name.tokenKind == .keyword(.static) }
                    && variable.bindings.contains { $0.pattern.as(IdentifierPatternSyntax.self)?.identifier.text == "name" }
            }
    }
}
