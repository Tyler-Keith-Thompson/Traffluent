import SwiftCompilerPlugin
import SwiftSyntaxMacros

/// The compiler plugin holding the `@Event` and `@Constrained` macros.
@main
struct Plugin: CompilerPlugin {
    let providingMacros: [any Macro.Type] = [EventMacro.self, ConstrainedMacro.self]
}
