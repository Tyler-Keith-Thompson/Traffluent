// The record @_DiscoverableEvent gives an event written by hand, and #__eventRecord, the record
// macro it and @Event call, pinned. Each test is self-contained.
//
// The record is pinned as the one #__eventRecord call, which assertMacroExpansion leaves unexpanded
// as it isn't in the table: the per-format declarations behind it are LinkerSets'. The function
// after it, whose symbol holds the event's name, the type's, is pinned as written.

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
    @Test("A struct gets the record @Event would give it, of the events kind and holding it as a __DiscoverableEvent, the conformance, and its name declared as Event's default gives it, with the struct's access")
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

                @_silgen_name("$linkerset_kind_65766E74_key_Opened") @used nonisolated func __macro_local_18linkerSetUniqueKeyfMu_() {
                }

                extension Opened: Events.__DiscoverableEvent {
                }

                nonisolated extension Opened {
                    public static var name: String {
                        String(describing: Self.self)
                    }
                }
                """,
            macroSpecs: ["_DiscoverableEvent": MacroSpec(type: DiscoverableEventMacro.self, conformances: ["__DiscoverableEvent"])],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test("A struct that already conforms to __DiscoverableEvent gets its record and its name, but no conformance")
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

                @_silgen_name("$linkerset_kind_65766E74_key_Opened") @used nonisolated func __macro_local_18linkerSetUniqueKeyfMu_() {
                }

                nonisolated extension Opened {
                    static var name: String {
                        String(describing: Self.self)
                    }
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

                    @_silgen_name("$linkerset_kind_65766E74_key_Opened") @used nonisolated static func __macro_local_18linkerSetUniqueKeyfMu_() {
                    }
                }

                extension Lifecycle.Opened: Events.__DiscoverableEvent {
                }

                nonisolated extension Lifecycle.Opened {
                    static var name: String {
                        String(describing: Self.self)
                    }
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

                nonisolated extension E {
                    static var name: String {
                        String(describing: Self.self)
                    }
                }
                """,
            diagnostics: [
                DiagnosticSpec(message: "'@_DiscoverableEvent' cannot apply to a generic type: a record holds one concrete type", line: 2, column: 9),
            ],
            macroSpecs: ["_DiscoverableEvent": MacroSpec(type: DiscoverableEventMacro.self, conformances: ["__DiscoverableEvent"])],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test("A static name the struct declares itself is an error at the member, as the record's key is the type's name; the struct still gets the conformance, but no name")
    func nameMember() {
        assertMacroExpansion(
            """
            @_DiscoverableEvent
            struct Opened {
                static let name = "opened"
            }
            """,
            expandedSource: """
                struct Opened {
                    static let name = "opened"
                }

                extension Opened: Events.__DiscoverableEvent {
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@_DiscoverableEvent names the event after its type, which no other event may share; remove this member, or rename the type",
                    line: 3, column: 5),
            ],
            macroSpecs: ["_DiscoverableEvent": MacroSpec(type: DiscoverableEventMacro.self, conformances: ["__DiscoverableEvent"])],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test("A struct in a private type gets its record and no key, as the key's function would be local to the file, as @Event's does")
    func inPrivateType() {
        assertMacroExpansion(
            """
            private enum Lifecycle {
                @_DiscoverableEvent
                struct Opened {
                }
            }
            """,
            expandedSource: """
                private enum Lifecycle {
                    struct Opened {
                    }

                    #__eventRecord(kind: 0x65766E74, storing: Lifecycle.Opened.self as any (Events.__DiscoverableEvent).Type)
                }

                extension Lifecycle.Opened: Events.__DiscoverableEvent {
                }

                nonisolated extension Lifecycle.Opened {
                    static var name: String {
                        String(describing: Self.self)
                    }
                }
                """,
            macroSpecs: ["_DiscoverableEvent": MacroSpec(type: DiscoverableEventMacro.self, conformances: ["__DiscoverableEvent"])],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test("A static name the struct declares itself is an error at the member in a private type too")
    func nameMemberInPrivateType() {
        assertMacroExpansion(
            """
            private enum Lifecycle {
                @_DiscoverableEvent
                struct Opened {
                    static let name = "opened"
                }
            }
            """,
            expandedSource: """
                private enum Lifecycle {
                    struct Opened {
                        static let name = "opened"
                    }
                }

                extension Lifecycle.Opened: Events.__DiscoverableEvent {
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@_DiscoverableEvent names the event after its type, which no other event may share; remove this member, or rename the type",
                    line: 4, column: 9),
            ],
            macroSpecs: ["_DiscoverableEvent": MacroSpec(type: DiscoverableEventMacro.self, conformances: ["__DiscoverableEvent"])],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test("A struct in a private member type is an error at the attribute naming the type, with no record, conformance or name, as @Event's is")
    func inPrivateMemberType() {
        assertMacroExpansion(
            """
            private struct Suite {
                private enum Lifecycle {
                    @_DiscoverableEvent
                    struct Opened {
                    }
                }
            }
            """,
            expandedSource: """
                private struct Suite {
                    private enum Lifecycle {
                        struct Opened {
                        }
                    }
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@_DiscoverableEvent conforms the type in an extension at file scope, where the private member type Lifecycle is hidden; make it fileprivate",
                    line: 3, column: 9),
            ],
            macroSpecs: ["_DiscoverableEvent": MacroSpec(type: DiscoverableEventMacro.self, conformances: ["__DiscoverableEvent"])],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test("A struct in a private member type that declares a static name gets both errors, as @Event reports every rule a struct breaks")
    func nameMemberInPrivateMemberType() {
        assertMacroExpansion(
            """
            struct Suite {
                private enum Lifecycle {
                    @_DiscoverableEvent
                    struct Opened {
                        static let name = "opened"
                    }
                }
            }
            """,
            expandedSource: """
                struct Suite {
                    private enum Lifecycle {
                        struct Opened {
                            static let name = "opened"
                        }
                    }
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@_DiscoverableEvent names the event after its type, which no other event may share; remove this member, or rename the type",
                    line: 5, column: 13),
                DiagnosticSpec(
                    message: "@_DiscoverableEvent conforms the type in an extension at file scope, where the private member type Lifecycle is hidden; make it fileprivate",
                    line: 3, column: 9),
            ],
            macroSpecs: ["_DiscoverableEvent": MacroSpec(type: DiscoverableEventMacro.self, conformances: ["__DiscoverableEvent"])],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test("A struct that is itself a private member type is an error with a Fix-It making it fileprivate, as @Event's is")
    func privateMemberStruct() {
        assertMacroExpansion(
            """
            enum Lifecycle {
                @_DiscoverableEvent
                private struct Opened {
                }
            }
            """,
            expandedSource: """
                enum Lifecycle {
                    private struct Opened {
                    }
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@_DiscoverableEvent conforms the type in an extension at file scope, where the private member type Opened is hidden; make it fileprivate",
                    line: 2, column: 5,
                    fixIts: [FixItSpec(message: "Make Opened fileprivate")]),
            ],
            macroSpecs: ["_DiscoverableEvent": MacroSpec(type: DiscoverableEventMacro.self, conformances: ["__DiscoverableEvent"])],
            fixedSource: """
                enum Lifecycle {
                    @_DiscoverableEvent
                    fileprivate struct Opened {
                    }
                }
                """,
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test("A struct in a fileprivate member type nested two levels deep gets its record, with no key, its conformance and its name")
    func inFileprivateMemberTypeTwoLevelsDeep() {
        assertMacroExpansion(
            """
            private struct Suite {
                fileprivate enum Fixtures {
                    fileprivate enum Lifecycle {
                        @_DiscoverableEvent
                        struct Opened {
                        }
                    }
                }
            }
            """,
            expandedSource: """
                private struct Suite {
                    fileprivate enum Fixtures {
                        fileprivate enum Lifecycle {
                            struct Opened {
                            }

                            #__eventRecord(kind: 0x65766E74, storing: Suite.Fixtures.Lifecycle.Opened.self as any (Events.__DiscoverableEvent).Type)
                        }
                    }
                }

                extension Suite.Fixtures.Lifecycle.Opened: Events.__DiscoverableEvent {
                }

                nonisolated extension Suite.Fixtures.Lifecycle.Opened {
                    static var name: String {
                        String(describing: Self.self)
                    }
                }
                """,
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
