import LinkerSetsMacroSupport
import SwiftSyntax

/// A macro that writes an event type's LinkerSets record: of Traffluent's event kind, `"evnt"`,
/// holding the type as an `any Events.__DiscoverableEvent.Type`, written by `#__eventRecord` rather
/// than LinkerSets' own `#linkerSetRecord`.
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
}
