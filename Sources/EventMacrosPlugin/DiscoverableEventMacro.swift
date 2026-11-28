import LinkerSetsMacroSupport
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

/// `@_DiscoverableEvent`: the record `@Event` would give an event written by hand, beside the
/// struct, and the conformance to `__DiscoverableEvent` the record holds the struct as; an error
/// instead, as `@Event` gives, for a struct in a private member type.
///
/// The library's own events (`SessionStarted`, `ScreenViewed`, …) are written by hand, so their
/// modules depend on EventMacros for this and not on LinkerSets, whose plugin would be a second
/// one in their build.
public struct DiscoverableEventMacro: ExtensionMacro, EventLinkerSetMacro {
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        // As @Event does: an extension at file scope can't name a private member type.
        if let diagnostic = PrivateMemberType.diagnostic(of: declaration, attribute: node, in: context) {
            context.diagnose(diagnostic)
            return []
        }
        let structure = declaration.as(StructDeclSyntax.self)
        let access = structure?.modifiers.first { [.keyword(.public), .keyword(.package)].contains($0.name.tokenKind) }
            .map { "\($0.name.text) " } ?? ""
        // As @Event does: the name always declared, the value Event's default gives, so another
        // declaration of it is a redeclaration and the name is always the key.
        let name = try ExtensionDeclSyntax(
            "nonisolated extension \(type.trimmed) {\n\(raw: access)static var name: String {\nString(describing: Self.self)\n}\n}"
        )
        // None beside a name member, which the peer reports; a redeclaration would add an error.
        let names = structure?.nameMember == nil ? [name] : []
        // Empty when the struct already conforms: the compiler passes only what's missing.
        guard !protocols.isEmpty else { return names }
        return [try ExtensionDeclSyntax("extension \(type.trimmed): Events.__DiscoverableEvent {}")] + names
    }

    /// The struct's record, beside it: none for one the extension reports as hidden in a private
    /// member type, as the record holds the struct as the `__DiscoverableEvent` the extension
    /// conforms it to, though a `name` member is still reported there.
    ///
    /// - Throws: A diagnostic at a `name` member the struct declares itself.
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard PrivateMemberType.types(around: declaration, in: context.lexicalContext).isEmpty else {
            // No record, but a name member is still reported, beside the extension's error, as
            // @Event reports every rule a struct breaks.
            _ = try uniqueKey(of: declaration, attribute: node)
            return []
        }
        return try recordPeers(of: node, providingPeersOf: declaration, in: context)
    }

    /// The type's name, which the event takes as its own.
    ///
    /// - Throws: A diagnostic at a `name` member the struct declares itself.
    public static func uniqueKey(of declaration: some DeclSyntaxProtocol, attribute: AttributeSyntax) throws -> String? {
        guard let structure = declaration.as(StructDeclSyntax.self) else { return nil }
        if let member = structure.nameMember {
            throw DiagnosticsError(diagnostics: [Diagnostic(node: member, message: EventMacroDiagnostic.discoverableNameMember)])
        }
        return structure.typeName
    }
}
