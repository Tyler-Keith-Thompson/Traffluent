import SwiftCompilerPlugin
import SwiftSyntaxMacros

/// The compiler plugin holding the `@Event` macro.
@main
struct Plugin: CompilerPlugin {
    let providingMacros: [any Macro.Type] = [EventMacro.self]
}
