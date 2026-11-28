import LinkerSetsMacroSupport
import SwiftSyntax
import SwiftSyntaxMacros

/// `#__eventRecord(kind:storing:)`: the record `@Event` and `@_DiscoverableEvent` write,
/// LinkerSetsMacroSupport's expansion of `#linkerSetRecord` under a name and module of
/// Traffluent's own.
public struct EventRecordMacro: DeclarationMacro {
    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        try LinkerSetRecordMacro.expansion(of: node, in: context)
    }
}
