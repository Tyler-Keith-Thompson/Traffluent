import SwiftCompilerPlugin
import SwiftSyntaxMacros

/// The compiler plugin holding the `@Event` and `@Constrained` macros, and `@_DiscoverableEvent`
/// and `#__eventRecord`, which write events' records.
@main
struct Plugin: CompilerPlugin {
    let providingMacros: [any Macro.Type] = [EventMacro.self, ConstrainedMacro.self, DiscoverableEventMacro.self, EventRecordMacro.self]
}
