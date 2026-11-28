import LinkerSetsMacroSupport
import SwiftSyntax
import SwiftSyntaxMacros

/// `@_DiscoverableEvent`: the record `@Event` would give an event written by hand, beside the
/// struct, and the conformance to `__DiscoverableEvent` the record holds the struct as.
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
        // Empty when the struct already conforms: the compiler passes only what's missing.
        guard !protocols.isEmpty else { return [] }
        return [try ExtensionDeclSyntax("extension \(type.trimmed): Events.__DiscoverableEvent {}")]
    }
}
