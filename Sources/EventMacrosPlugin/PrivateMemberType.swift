import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

/// A type declared `private` inside another type or an extension: an event's struct, or a type it
/// is nested in, that the extension `@Event` and `@_DiscoverableEvent` add can't name.
// Swift places an extension macro's extension at file scope, and looks its extended type up from
// there, where a private member type is hidden (swiftlang/swift#77023, open on Swift 6.4.2): the
// expansion fails with "'X' is inaccessible due to 'private' protection level". Nothing else can
// add a conformance (a member macro can't, and no peer can widen an enclosing type's access), so
// the macros refuse such a struct at the attribute instead, naming each type to make fileprivate,
// which an extension in the file can see. A private type at file scope is fileprivate already, and
// a private extension's members are fileprivate too.
//
// The Fix-It is offered only for the struct's own `private`: the compiler drops a macro's edit to
// an enclosing declaration, which the macro sees only as its lexical context (checked on Swift
// 6.4.2), so a Fix-It there would change nothing.
struct PrivateMemberType {
    /// The type's name.
    let name: String
    /// Its `private` keyword.
    let keyword: TokenSyntax
    /// Whether this is the declaration the macro is attached to, rather than a type around it.
    let isAttachedDeclaration: Bool

    /// Each private member type that `declaration` is or is nested in, innermost first.
    ///
    /// - Parameters:
    ///   - declaration: The declaration the macro is attached to.
    ///   - lexicalContext: The expansion's lexical context, innermost first.
    static func types(around declaration: some DeclSyntaxProtocol, in lexicalContext: [Syntax]) -> [PrivateMemberType] {
        // A declaration in a function's body (or a closure's, or an accessor's) is a local type,
        // which the compiler refuses an extension macro on with an error of its own, so nothing
        // is said here, as LinkerSets' scope checks say nothing of it either.
        guard lexicalContext.allSatisfy({ $0.isProtocol(DeclGroupSyntax.self) }) else { return [] }
        // Every scope but the outermost, which sits at file scope, where private is fileprivate;
        // each other one is a member of the type or extension around it.
        let scopes = ([Syntax(declaration)] + lexicalContext).dropLast()
        return scopes.enumerated().compactMap { index, scope in
            guard let name = scope.typeName, let keyword = scope.privateKeyword else { return nil }
            return PrivateMemberType(name: name, keyword: keyword, isAttachedDeclaration: index == 0)
        }
    }

    /// An error at `attribute` when `declaration` is or is nested in a private member type, naming
    /// each such type, with a Fix-It that makes `declaration` fileprivate when it is the only one;
    /// `nil` otherwise.
    static func diagnostic(of declaration: some DeclSyntaxProtocol, attribute: AttributeSyntax, in context: some MacroExpansionContext) -> Diagnostic? {
        let types = types(around: declaration, in: context.lexicalContext)
        guard let innermost = types.first else { return nil }
        let fixIts = types.count == 1 && innermost.isAttachedDeclaration
            ? [FixIt(message: EventMacroFixIt.makeFileprivate(name: innermost.name), changes: [
                .replace(oldNode: Syntax(innermost.keyword), newNode: Syntax(innermost.keyword.with(\.tokenKind, .keyword(.fileprivate)))),
            ])]
            : []
        return Diagnostic(
            node: attribute,
            message: EventMacroDiagnostic.privateMemberType(macro: "@" + attribute.attributeName.trimmedDescription, names: types.map(\.name)),
            fixIts: fixIts
        )
    }
}

extension Syntax {
    /// The name of the type this declares, or `nil` for an extension, which declares none.
    fileprivate var typeName: String? {
        asProtocol(NamedDeclSyntax.self)?.name.text
    }

    /// The `private` keyword among this declaration's modifiers, if it has one with no detail,
    /// as LinkerSets reads it.
    fileprivate var privateKeyword: TokenSyntax? {
        asProtocol(WithModifiersSyntax.self)?.modifiers
            .first { $0.name.tokenKind == .keyword(.private) && $0.detail == nil }?
            .name
    }
}
