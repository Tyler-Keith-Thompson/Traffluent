// The record @_DiscoverableEvent gives an event written by hand, and #__eventRecord, the record
// macro it and @Event call, pinned. Each test is self-contained.
//
// The record is pinned as the one #__eventRecord call, which assertMacroExpansion leaves unexpanded
// as it isn't in the table: the per-format declarations behind it are LinkerSets'.

import EventMacrosPlugin
import LinkerSetsMacroSupport
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacros
import SwiftSyntaxMacrosGenericTestSupport
import Testing

@Suite("@_DiscoverableEvent and #__eventRecord expansions")
struct DiscoverableEventMacroExpansionTests {
    @Test("A struct gets the record @Event would give it, of the events kind and holding it as a __DiscoverableEvent, and the conformance")
    func record() {
        assertMacroExpansion(
            """
            @_DiscoverableEvent
            public struct Opened: Event, Codable {
            }
            """,
            expandedSource: """
                public struct Opened: Event, Codable {
                }

                private enum __macro_local_15linkerSetRecordfMu_ {
                    #__eventRecord(kind: 0x65766E74, storing: Opened.self as any (Events.__DiscoverableEvent).Type)
                }

                extension Opened: Events.__DiscoverableEvent {
                }
                """,
            macroSpecs: ["_DiscoverableEvent": MacroSpec(type: DiscoverableEventMacro.self, conformances: ["__DiscoverableEvent"])],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test("A struct that already conforms to __DiscoverableEvent gets its record and no extension")
    func alreadyConforming() {
        assertMacroExpansion(
            """
            @_DiscoverableEvent
            struct Opened: __DiscoverableEvent {
            }
            """,
            expandedSource: """
                struct Opened: __DiscoverableEvent {
                }

                private enum __macro_local_15linkerSetRecordfMu_ {
                    #__eventRecord(kind: 0x65766E74, storing: Opened.self as any (Events.__DiscoverableEvent).Type)
                }
                """,
            macroSpecs: ["_DiscoverableEvent": MacroSpec(type: DiscoverableEventMacro.self, conformances: [])],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test("A nested struct's record is a member of its enclosing type, naming the struct through it, and so is its extension")
    func nested() {
        assertMacroExpansion(
            """
            enum Lifecycle {
                @_DiscoverableEvent
                struct Opened {
                }
            }
            """,
            expandedSource: """
                enum Lifecycle {
                    struct Opened {
                    }

                    #__eventRecord(kind: 0x65766E74, storing: Lifecycle.Opened.self as any (Events.__DiscoverableEvent).Type)
                }

                extension Lifecycle.Opened: Events.__DiscoverableEvent {
                }
                """,
            macroSpecs: ["_DiscoverableEvent": MacroSpec(type: DiscoverableEventMacro.self, conformances: ["__DiscoverableEvent"])],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test("A generic struct is refused with an error at its generic clause, as a record holds one concrete type, and still gets the conformance")
    func generic() {
        assertMacroExpansion(
            """
            @_DiscoverableEvent
            struct E<T> {}
            """,
            expandedSource: """
                struct E<T> {}

                extension E: Events.__DiscoverableEvent {
                }
                """,
            diagnostics: [
                DiagnosticSpec(message: "'@_DiscoverableEvent' cannot apply to a generic type: a record holds one concrete type", line: 2, column: 9),
            ],
            macroSpecs: ["_DiscoverableEvent": MacroSpec(type: DiscoverableEventMacro.self, conformances: ["__DiscoverableEvent"])],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test("#__eventRecord expands to what LinkerSets' #linkerSetRecord does for the same arguments")
    func recordMacro() throws {
        let node = try #require(DeclSyntax("#__eventRecord(kind: 0x65766E74, storing: Opened.self)").as(MacroExpansionDeclSyntax.self))
        let expected = try LinkerSetRecordMacro.expansion(of: node, in: BasicMacroExpansionContext()).map(\.description)

        let actual = try EventRecordMacro.expansion(of: node, in: BasicMacroExpansionContext()).map(\.description)

        #expect(actual == expected)
    }
}
