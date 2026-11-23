import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

/// `@Constrained`: adds nothing itself. `@Event` reads its keywords from the property it is
/// attached to; this only reports where it can't be read: on anything but a stored instance
/// property of an `@Event` struct.
public struct ConstrainedMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        let isStored = declaration.as(VariableDeclSyntax.self).map { variable in
            !variable.isStatic && !variable.bindings.contains { $0.isComputed }
        } ?? false
        let inEvent = context.lexicalContext.first?.as(StructDeclSyntax.self)?.attributes.contains { attribute in
            let name = attribute.as(AttributeSyntax.self)?.attributeName.trimmedDescription
            return name == "Event" || name == "EventMacros.Event"
        } ?? false
        if !isStored || !inEvent {
            context.diagnose(Diagnostic(node: node, message: EventMacroDiagnostic.constrainedNotStoredProperty))
        }
        return []
    }
}
