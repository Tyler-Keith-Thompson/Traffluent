import LinkerSetsMacroSupport
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

/// A macro that writes an event type's LinkerSets record: of Traffluent's event kind, `"evnt"`,
/// holding the type as an `any Events.__DiscoverableEvent.Type`, written by `#__eventRecord` rather
/// than LinkerSets' own `#linkerSetRecord`, with the event's name as its unique key.
///
/// `@Event` and `@_DiscoverableEvent` conform to it, so their records agree.
public protocol EventLinkerSetMacro: LinkerSetMacro {}

extension EventLinkerSetMacro {
    // The kind Events reads, LinkerSetKind.events. A plugin depends on packages' products only, so
    // it can't take the number from Events; DiscoveredEventTests' everyEvent, which lists events of
    // both macros, fails when the two differ, as no event would then be found.
    public static func kind(of attribute: AttributeSyntax) -> UInt32 { 0x6576_6E74 }  // "evnt"

    // Qualified with its module, so a type of the same name where the macro is used can't stand in.
    public static func requiredConformance(of attribute: AttributeSyntax) -> TypeSyntax? {
        "Events.__DiscoverableEvent"
    }

    // EventMacros' own record macro (EventRecordMacro), so a module that writes events' records
    // depends on EventMacros and LinkerSetsRuntime, never on LinkerSets and its plugin.
    public static var recordMacroName: String { "__eventRecord" }

    /// The event's name, `Event.name`, which no other event of one linked image may share: the
    /// `name:` argument's value, or the type's name as `String(describing:)` writes it, `Event`'s
    /// default, which `@Event` declares as the name.
    ///
    /// - Throws: A diagnostic at a `name:` argument that isn't a string literal.
    // The name alone, not its version: a store built from a list takes one type per name,
    // whatever its version. LinkerSets refuses a key it can't read at compile time, so a name the
    // macro can't read is refused too, rather than checked under the type's name, which isn't the
    // event's.
    // @Event declares the name it gives here, so a name declared anywhere else is a redeclaration;
    // its peer reports a name member before LinkerSets asks for the key.
    public static func uniqueKey(of declaration: some DeclSyntaxProtocol, attribute: AttributeSyntax) throws -> String? {
        guard let structure = declaration.as(StructDeclSyntax.self) else { return nil }
        guard let name = EventArguments.arguments(of: attribute).arguments.name else { return structure.typeName }
        guard let value = name.as(StringLiteralExprSyntax.self)?.representedLiteralValue else {
            throw DiagnosticsError(diagnostics: [Diagnostic(node: name, message: EventMacroDiagnostic.nameNotALiteral)])
        }
        return value
    }
}

extension EventLinkerSetMacro {
    /// The event's record, as a peer: ``eventRecordPeers(of:providingPeersOf:in:)``.
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        try eventRecordPeers(of: node, providingPeersOf: declaration, in: context)
    }

    /// The event's record, as a peer: LinkerSets' `recordPeers(of:providingPeersOf:in:)`, with the
    /// unique key, or without it in a private or fileprivate type or extension.
    ///
    /// - Throws: What `recordPeers(of:providingPeersOf:in:)` throws.
    // In a private or fileprivate scope the symbol that checks the name would be local to its
    // file, which the linker never compares, so LinkerSets refuses a unique key there. The event
    // gets its record without the check instead of failing to compile: stores and plans still
    // refuse a duplicate when they read the events, and a test whose fixtures reuse an event's
    // name declares them in a private suite.
    public static func eventRecordPeers(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard !context.isInPrivateScope else {
            return try UncheckedEventRecord.recordPeers(of: node, providingPeersOf: declaration, in: context)
        }
        return try recordPeers(of: node, providingPeersOf: declaration, in: context)
    }
}

/// An event's record in a private or fileprivate scope: the same record, with no unique key.
private enum UncheckedEventRecord: EventLinkerSetMacro {
    static func uniqueKey(of declaration: some DeclSyntaxProtocol, attribute: AttributeSyntax) -> String? {
        nil
    }
}

extension MacroExpansionContext {
    /// Whether a type or extension around the declaration is `private` or `fileprivate`, as
    /// LinkerSets judges it: then a symbol declared beside the declaration is local to its file.
    fileprivate var isInPrivateScope: Bool {
        lexicalContext.contains { scope in
            scope.asProtocol(WithModifiersSyntax.self)?.modifiers.contains { modifier in
                [.keyword(.private), .keyword(.fileprivate)].contains(modifier.name.tokenKind) && modifier.detail == nil
            } == true
        }
    }
}
