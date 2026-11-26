// The errors @Event reports where it can't expand, and the nodes it reports them at. A struct
// with an error gets no extension. Each test is self-contained.

import EventMacrosPlugin
import SwiftSyntax
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacros
import SwiftSyntaxMacrosGenericTestSupport
import Testing

@Suite("@Event diagnostics")
struct EventMacroDiagnosticTests {
    @Test("Anything but a struct is an error at the attribute", arguments: ["class", "enum", "actor"])
    func notAStruct(keyword: String) {
        assertMacroExpansion(
            """
            @Event
            \(keyword) Opened {
            }
            """,
            expandedSource: """
                \(keyword) Opened {
                }
                """,
            diagnostics: [DiagnosticSpec(message: "@Event applies only to a struct", line: 1, column: 1)],
            macroSpecs: ["Event": MacroSpec(type: EventMacro.self, conformances: ["Event", "Encodable", "Decodable"])],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test("A stored property with no type annotation is an error at its binding")
    func missingTypeAnnotation() {
        assertMacroExpansion(
            """
            @Event
            struct Tapped {
                var count = 0
                var screen: String
            }
            """,
            expandedSource: """
                struct Tapped {
                    var count = 0
                    var screen: String
                }
                """,
            diagnostics: [DiagnosticSpec(message: "@Event needs the type of every stored property written out; add a type annotation", line: 3, column: 9)],
            macroSpecs: ["Event": MacroSpec(type: EventMacro.self, conformances: ["Event", "Encodable", "Decodable"])],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test("A binding with an initial value, or before one, isn't given a later binding's annotation")
    func sharedAnnotationAfterInitializer() {
        assertMacroExpansion(
            """
            @Event
            struct Tapped {
                var a = 1, b = 2, c: Int
                var x, y = 2, z: Int
            }
            """,
            expandedSource: """
                struct Tapped {
                    var a = 1, b = 2, c: Int
                    var x, y = 2, z: Int
                }
                """,
            diagnostics: [
                DiagnosticSpec(message: "@Event needs the type of every stored property written out; add a type annotation", line: 3, column: 9),
                DiagnosticSpec(message: "@Event needs the type of every stored property written out; add a type annotation", line: 3, column: 16),
                DiagnosticSpec(message: "@Event needs the type of every stored property written out; add a type annotation", line: 4, column: 9),
                DiagnosticSpec(message: "@Event needs the type of every stored property written out; add a type annotation", line: 4, column: 12),
            ],
            macroSpecs: ["Event": MacroSpec(type: EventMacro.self, conformances: ["Event", "Encodable", "Decodable"])],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test("A lazy property is an error at its declaration")
    func lazyProperty() {
        assertMacroExpansion(
            """
            @Event
            struct Tapped {
                lazy var count: Int = 0
            }
            """,
            expandedSource: """
                struct Tapped {
                    lazy var count: Int = 0
                }
                """,
            diagnostics: [DiagnosticSpec(message: "@Event can't encode a lazy property; make it a stored or a computed property", line: 3, column: 5)],
            macroSpecs: ["Event": MacroSpec(type: EventMacro.self, conformances: ["Event", "Encodable", "Decodable"])],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test("A destructuring pattern is an error at the pattern")
    func destructuringPattern() {
        assertMacroExpansion(
            """
            @Event
            struct Moved {
                var (x, y): (Int, Int)
            }
            """,
            expandedSource: """
                struct Moved {
                    var (x, y): (Int, Int)
                }
                """,
            diagnostics: [DiagnosticSpec(message: "@Event can't encode a destructuring pattern; declare each property on its own", line: 3, column: 9)],
            macroSpecs: ["Event": MacroSpec(type: EventMacro.self, conformances: ["Event", "Encodable", "Decodable"])],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test("A name that isn't a plain string literal is an error at the argument", arguments: [#"eventName"#, #""signed_\(up)""#])
    func nameNotALiteral(name: String) {
        assertMacroExpansion(
            """
            @Event(name: \(name))
            struct SignedUp {
            }
            """,
            expandedSource: """
                struct SignedUp {
                }
                """,
            diagnostics: [DiagnosticSpec(message: "@Event's name must be a string literal without interpolation", line: 1, column: 14)],
            macroSpecs: ["Event": MacroSpec(type: EventMacro.self, conformances: ["Event", "Encodable", "Decodable"])],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test("An empty name is an error at the argument", arguments: [#""""#, ##"#""#"##])
    func emptyName(name: String) {
        assertMacroExpansion(
            """
            @Event(name: \(name))
            struct SignedUp {
            }
            """,
            expandedSource: """
                struct SignedUp {
                }
                """,
            diagnostics: [DiagnosticSpec(message: "@Event's name must not be empty", line: 1, column: 14)],
            macroSpecs: ["Event": MacroSpec(type: EventMacro.self, conformances: ["Event", "Encodable", "Decodable"])],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test("A version that isn't a positive integer literal is an error at the argument", arguments: ["0", "-1", "latest"])
    func versionNotAPositiveLiteral(version: String) {
        assertMacroExpansion(
            """
            @Event(version: \(version))
            struct SignedUp {
            }
            """,
            expandedSource: """
                struct SignedUp {
                }
                """,
            diagnostics: [DiagnosticSpec(message: "@Event's version must be a positive integer literal", line: 1, column: 17)],
            macroSpecs: ["Event": MacroSpec(type: EventMacro.self, conformances: ["Event", "Encodable", "Decodable"])],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test("Every error in one struct is reported, and the struct gets no extension")
    func everyError() {
        assertMacroExpansion(
            """
            @Event(name: "", version: 0)
            struct Broken {
                var count = 0
                lazy var total: Int = 0
            }
            """,
            expandedSource: """
                struct Broken {
                    var count = 0
                    lazy var total: Int = 0
                }
                """,
            diagnostics: [
                DiagnosticSpec(message: "@Event's name must not be empty", line: 1, column: 14),
                DiagnosticSpec(message: "@Event's version must be a positive integer literal", line: 1, column: 27),
                DiagnosticSpec(message: "@Event needs the type of every stored property written out; add a type annotation", line: 3, column: 9),
                DiagnosticSpec(message: "@Event can't encode a lazy property; make it a stored or a computed property", line: 4, column: 5),
            ],
            macroSpecs: ["Event": MacroSpec(type: EventMacro.self, conformances: ["Event", "Encodable", "Decodable"])],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }
}
