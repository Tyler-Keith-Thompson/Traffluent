// @Event on a struct that is, or is nested in, a type declared private inside another type or an
// extension: the extension @Event adds sits at file scope, where Swift can't see such a type, so the
// macro reports it at the attribute and adds nothing. A fileprivate member type, a private type at
// file scope and a private extension's types expand as usual. Each test is self-contained.

import EventMacrosPlugin
import SwiftSyntax
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacros
import SwiftSyntaxMacrosGenericTestSupport
import Testing

@Suite("@Event in private member types")
struct EventMacroPrivateMemberTypeTests {
    @Test("A struct in a private member type is an error at the attribute naming the type, with no record, no extension and no Fix-It, as the macro can't edit the type around it")
    func inPrivateMemberType() {
        assertMacroExpansion(
            """
            private struct Suite {
                private enum EarlierVersions {
                    @Event(name: "rated")
                    struct Rated {
                        var stars: Int
                    }
                }
            }
            """,
            expandedSource: """
                private struct Suite {
                    private enum EarlierVersions {
                        struct Rated {
                            var stars: Int
                        }
                    }
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@Event conforms the type in an extension at file scope, where the private member type EarlierVersions is hidden; make it fileprivate",
                    line: 3, column: 9),
            ],
            macroSpecs: ["Event": MacroSpec(type: EventMacro.self, conformances: ["Event", "Encodable", "Decodable", "__DiscoverableEvent"])],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test("A struct that is itself a private member type is an error with a Fix-It making it fileprivate")
    func privateMemberStruct() {
        assertMacroExpansion(
            """
            struct Suite {
                @Event(name: "rated")
                private struct Rated {
                }
            }
            """,
            expandedSource: """
                struct Suite {
                    private struct Rated {
                    }
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@Event conforms the type in an extension at file scope, where the private member type Rated is hidden; make it fileprivate",
                    line: 2, column: 5,
                    fixIts: [FixItSpec(message: "Make Rated fileprivate")]),
            ],
            macroSpecs: ["Event": MacroSpec(type: EventMacro.self, conformances: ["Event", "Encodable", "Decodable", "__DiscoverableEvent"])],
            fixedSource: """
                struct Suite {
                    @Event(name: "rated")
                    fileprivate struct Rated {
                    }
                }
                """,
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test("A private struct in a private member type names both, innermost first, with no Fix-It, as the struct's alone wouldn't be enough")
    func twoPrivateMemberTypes() {
        assertMacroExpansion(
            """
            struct Suite {
                private enum EarlierVersions {
                    @Event(name: "rated")
                    private struct Rated {
                    }
                }
            }
            """,
            expandedSource: """
                struct Suite {
                    private enum EarlierVersions {
                        private struct Rated {
                        }
                    }
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@Event conforms the type in an extension at file scope, where the private member types Rated and EarlierVersions are hidden; make them fileprivate",
                    line: 3, column: 9),
            ],
            macroSpecs: ["Event": MacroSpec(type: EventMacro.self, conformances: ["Event", "Encodable", "Decodable", "__DiscoverableEvent"])],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test("Three private member types are named as a list, the last after an and, and a private type beside them is not named")
    func threePrivateMemberTypes() {
        assertMacroExpansion(
            """
            struct Suite {
                private enum Fixtures {
                    private enum EarlierVersions {
                        @Event(name: "rated")
                        private struct Rated {
                        }
                    }
                }
                private enum Other {
                }
            }
            """,
            expandedSource: """
                struct Suite {
                    private enum Fixtures {
                        private enum EarlierVersions {
                            private struct Rated {
                            }
                        }
                    }
                    private enum Other {
                    }
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@Event conforms the type in an extension at file scope, where the private member types Rated, EarlierVersions and Fixtures are hidden; make them fileprivate",
                    line: 4, column: 13),
            ],
            macroSpecs: ["Event": MacroSpec(type: EventMacro.self, conformances: ["Event", "Encodable", "Decodable", "__DiscoverableEvent"])],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test("A struct in a type declared private in an extension is an error too: the extension's members are hidden from the rest of the file as a type's are")
    func inPrivateTypeOfExtension() {
        assertMacroExpansion(
            """
            extension Shelf {
                private enum Fixtures {
                    @Event(name: "opened")
                    struct Opened {
                    }
                }
            }
            """,
            expandedSource: """
                extension Shelf {
                    private enum Fixtures {
                        struct Opened {
                        }
                    }
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@Event conforms the type in an extension at file scope, where the private member type Fixtures is hidden; make it fileprivate",
                    line: 3, column: 9),
            ],
            macroSpecs: ["Event": MacroSpec(type: EventMacro.self, conformances: ["Event", "Encodable", "Decodable", "__DiscoverableEvent"])],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test("A struct in a fileprivate member type nested two levels deep in a private type gets its record, with no key, and its extension")
    func inFileprivateMemberTypeTwoLevelsDeep() {
        assertMacroExpansion(
            """
            private struct Suite {
                fileprivate enum Fixtures {
                    fileprivate enum EarlierVersions {
                        @Event(name: "rated")
                        struct Rated {
                        }
                    }
                }
            }
            """,
            expandedSource: """
                private struct Suite {
                    fileprivate enum Fixtures {
                        fileprivate enum EarlierVersions {
                            struct Rated {
                            }

                            #__eventRecord(kind: 0x65766E74, storing: Suite.Fixtures.EarlierVersions.Rated.self as any (Events.__DiscoverableEvent).Type)
                        }
                    }
                }

                nonisolated extension Suite.Fixtures.EarlierVersions.Rated: Events.Event, Swift.Encodable, Swift.Decodable, Events.__DiscoverableEvent {
                    static var name: String {
                        "rated"
                    }

                    static var schema: Events.EventSchema {
                        Events.EventSchema(name: Self.name, version: Self.schemaVersion, consentCategory: Self.consentCategory, properties: [])
                    }

                    private enum CodingKeys: Swift.CodingKey {
                    }

                    func encode(to encoder: any Swift.Encoder) throws {
                        _ = encoder.container(keyedBy: CodingKeys.self)
                    }

                    init(from decoder: any Swift.Decoder) throws {
                        _ = try decoder.container(keyedBy: CodingKeys.self)
                    }
                }
                """,
            macroSpecs: ["Event": MacroSpec(type: EventMacro.self, conformances: ["Event", "Encodable", "Decodable", "__DiscoverableEvent"])],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test("A struct in a private extension's type gets its record, with no key, and its extension: the extension's members are fileprivate")
    func inPrivateExtension() {
        assertMacroExpansion(
            """
            private extension Shelf {
                enum Fixtures {
                    @Event(name: "opened")
                    struct Opened {
                    }
                }
            }
            """,
            expandedSource: """
                private extension Shelf {
                    enum Fixtures {
                        struct Opened {
                        }

                        #__eventRecord(kind: 0x65766E74, storing: Shelf.Fixtures.Opened.self as any (Events.__DiscoverableEvent).Type)
                    }
                }

                nonisolated extension Shelf.Fixtures.Opened: Events.Event, Swift.Encodable, Swift.Decodable, Events.__DiscoverableEvent {
                    static var name: String {
                        "opened"
                    }

                    static var schema: Events.EventSchema {
                        Events.EventSchema(name: Self.name, version: Self.schemaVersion, consentCategory: Self.consentCategory, properties: [])
                    }

                    private enum CodingKeys: Swift.CodingKey {
                    }

                    func encode(to encoder: any Swift.Encoder) throws {
                        _ = encoder.container(keyedBy: CodingKeys.self)
                    }

                    init(from decoder: any Swift.Decoder) throws {
                        _ = try decoder.container(keyedBy: CodingKeys.self)
                    }
                }
                """,
            macroSpecs: ["Event": MacroSpec(type: EventMacro.self, conformances: ["Event", "Encodable", "Decodable", "__DiscoverableEvent"])],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test("A struct in a private method is no private member type: the macro reports nothing, leaving the compiler's one error for a local type")
    func inPrivateMethod() {
        assertMacroExpansion(
            """
            struct Suite {
                private func open() {
                    @Event(name: "opened")
                    struct Opened {
                    }
                }
            }
            """,
            // The test's expansion adds the extension the compiler refuses on a local type
            // (//Tests/CompileFailures:EventInFunction).
            expandedSource: """
                struct Suite {
                    private func open() {
                        struct Opened {
                        }
                    }
                }

                nonisolated extension Suite.open.Opened: Events.Event, Swift.Encodable, Swift.Decodable {
                    static var name: String {
                        "opened"
                    }

                    static var schema: Events.EventSchema {
                        Events.EventSchema(name: Self.name, version: Self.schemaVersion, consentCategory: Self.consentCategory, properties: [])
                    }

                    private enum CodingKeys: Swift.CodingKey {
                    }

                    func encode(to encoder: any Swift.Encoder) throws {
                        _ = encoder.container(keyedBy: CodingKeys.self)
                    }

                    init(from decoder: any Swift.Decoder) throws {
                        _ = try decoder.container(keyedBy: CodingKeys.self)
                    }
                }
                """,
            macroSpecs: ["Event": MacroSpec(type: EventMacro.self, conformances: ["Event", "Encodable", "Decodable", "__DiscoverableEvent"])],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test("A struct in a method of a private member type is a local type: the macro reports nothing, leaving the compiler's one error, though the type around the method is hidden")
    func inMethodOfPrivateMemberType() {
        assertMacroExpansion(
            """
            struct Suite {
                private struct Fixtures {
                    func open() {
                        @Event(name: "opened")
                        struct Opened {
                        }
                    }
                }
            }
            """,
            // The test's expansion adds the extension the compiler refuses on a local type
            // (//Tests/CompileFailures:EventInFunction).
            expandedSource: """
                struct Suite {
                    private struct Fixtures {
                        func open() {
                            struct Opened {
                            }
                        }
                    }
                }

                nonisolated extension Suite.Fixtures.open.Opened: Events.Event, Swift.Encodable, Swift.Decodable {
                    static var name: String {
                        "opened"
                    }

                    static var schema: Events.EventSchema {
                        Events.EventSchema(name: Self.name, version: Self.schemaVersion, consentCategory: Self.consentCategory, properties: [])
                    }

                    private enum CodingKeys: Swift.CodingKey {
                    }

                    func encode(to encoder: any Swift.Encoder) throws {
                        _ = encoder.container(keyedBy: CodingKeys.self)
                    }

                    init(from decoder: any Swift.Decoder) throws {
                        _ = try decoder.container(keyedBy: CodingKeys.self)
                    }
                }
                """,
            macroSpecs: ["Event": MacroSpec(type: EventMacro.self, conformances: ["Event", "Encodable", "Decodable", "__DiscoverableEvent"])],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test("A struct in a private member type of a final class or an actor is an error naming the type, as in a struct", arguments: ["final class", "actor"])
    func inPrivateMemberTypeOfReferenceType(container: String) {
        assertMacroExpansion(
            """
            \(container) Suite {
                private enum Fixtures {
                    @Event(name: "opened")
                    struct Opened {
                    }
                }
            }
            """,
            expandedSource: """
                \(container) Suite {
                    private enum Fixtures {
                        struct Opened {
                        }
                    }
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@Event conforms the type in an extension at file scope, where the private member type Fixtures is hidden; make it fileprivate",
                    line: 3, column: 9),
            ],
            macroSpecs: ["Event": MacroSpec(type: EventMacro.self, conformances: ["Event", "Encodable", "Decodable", "__DiscoverableEvent"])],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test("A type marked private itself inside a private extension is an error: the extension's private makes its members fileprivate, the member's own private hides it")
    func privateMemberOfPrivateExtension() {
        assertMacroExpansion(
            """
            private extension Shelf {
                private enum Fixtures {
                    @Event(name: "opened")
                    struct Opened {
                    }
                }
            }
            """,
            expandedSource: """
                private extension Shelf {
                    private enum Fixtures {
                        struct Opened {
                        }
                    }
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@Event conforms the type in an extension at file scope, where the private member type Fixtures is hidden; make it fileprivate",
                    line: 3, column: 9),
            ],
            macroSpecs: ["Event": MacroSpec(type: EventMacro.self, conformances: ["Event", "Encodable", "Decodable", "__DiscoverableEvent"])],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test("A private struct in a private type at file scope gets the Fix-It: the type around it is fileprivate, so the struct is the only one hidden")
    func privateMemberOfFileScopePrivateType() {
        assertMacroExpansion(
            """
            private struct Suite {
                @Event(name: "rated")
                private struct Rated {
                }
            }
            """,
            expandedSource: """
                private struct Suite {
                    private struct Rated {
                    }
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@Event conforms the type in an extension at file scope, where the private member type Rated is hidden; make it fileprivate",
                    line: 2, column: 5,
                    fixIts: [FixItSpec(message: "Make Rated fileprivate")]),
            ],
            macroSpecs: ["Event": MacroSpec(type: EventMacro.self, conformances: ["Event", "Encodable", "Decodable", "__DiscoverableEvent"])],
            fixedSource: """
                private struct Suite {
                    @Event(name: "rated")
                    fileprivate struct Rated {
                    }
                }
                """,
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test("A struct in a private member type that also breaks another rule gets both errors, the scope's first")
    func withOtherError() {
        assertMacroExpansion(
            """
            struct Suite {
                private enum EarlierVersions {
                    @Event(name: "")
                    struct Rated {
                    }
                }
            }
            """,
            expandedSource: """
                struct Suite {
                    private enum EarlierVersions {
                        struct Rated {
                        }
                    }
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@Event conforms the type in an extension at file scope, where the private member type EarlierVersions is hidden; make it fileprivate",
                    line: 3, column: 9),
                DiagnosticSpec(message: "@Event's name must not be empty", line: 3, column: 22),
            ],
            macroSpecs: ["Event": MacroSpec(type: EventMacro.self, conformances: ["Event", "Encodable", "Decodable", "__DiscoverableEvent"])],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }
}
