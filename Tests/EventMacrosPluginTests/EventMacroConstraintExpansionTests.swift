// The expansions @Constrained leads @Event to, pinned, and the errors either reports. Each test is
// self-contained.

import EventMacrosPlugin
import SwiftSyntax
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacros
import SwiftSyntaxMacrosGenericTestSupport
import Testing

@Suite("@Constrained expansions")
struct EventMacroConstraintExpansionTests {
    @Test("Declared constraints join the schema's keywords, typed by the property, and are checked in order, an optional's when it holds a value")
    func structure() {
        assertMacroExpansion(
            #"""
            @Event
            public struct Searched {
                @Constrained(.minLength(1), .maxLength(8))
                public var query: String
                @Constrained(.minimum(-1.5))
                @Constrained(.maximum(10))
                public var ratio: Double?
                public var page: Int
            }
            """#,
            expandedSource: #"""
                public struct Searched {
                    public var query: String
                    public var ratio: Double?
                    public var page: Int
                }

                extension Searched: Events.Event, Persistence.BinaryCodable {
                    public static var schema: Events.EventSchema {
                        Events.EventSchema(name: Self.name, version: 1, consentCategory: Self.consentCategory, properties: [
                            Events.EventSchema.Property(name: "query", typeName: "String", isOptional: false, keywords: Events.ValidationKeyword.keywords(of: \Self.query) + ([.minLength(1), .maxLength(8)] as [Events.Constraint<String>]).map(\.keyword)),
                            Events.EventSchema.Property(name: "ratio", typeName: "Double", isOptional: true, keywords: Events.ValidationKeyword.keywords(of: \Self.ratio) + ([.minimum(-1.5), .maximum(10)] as [Events.Constraint<Double>]).map(\.keyword)),
                            Events.EventSchema.Property(name: "page", typeName: "Int", isOptional: false, keywords: Events.ValidationKeyword.keywords(of: \Self.page)),
                        ])
                    }

                    public func constraintViolation() -> Events.ConstraintViolation? {
                        for constraint: Events.Constraint<String> in [.minLength(1), .maxLength(8)] where !constraint.isSatisfied(by: self.query) {
                            return Events.ConstraintViolation(property: "query", keyword: constraint.keyword)
                        }
                        if let value = self.ratio {
                            for constraint: Events.Constraint<Double> in [.minimum(-1.5), .maximum(10)] where !constraint.isSatisfied(by: value) {
                                return Events.ConstraintViolation(property: "ratio", keyword: constraint.keyword)
                            }
                        }
                        return nil
                    }

                    private static func requireBinaryCodable(query: KeyPath<Self, some Persistence.BinaryCodable>) {
                    }

                    private static func requireBinaryCodable(ratio: KeyPath<Self, some Persistence.BinaryCodable>) {
                    }

                    private static func requireBinaryCodable(page: KeyPath<Self, some Persistence.BinaryCodable>) {
                    }

                    private static var binaryCodableRequirements: Void {
                        requireBinaryCodable(query: \.query)
                        requireBinaryCodable(ratio: \.ratio)
                        requireBinaryCodable(page: \.page)
                    }

                    public func encode(to encoder: inout Persistence.BinaryEncoder) {
                        encoder.encodeMap { map in
                            map.encode(self.query, forKey: "query")
                            map.encode(self.ratio, forKey: "ratio")
                            map.encode(self.page, forKey: "page")
                        }
                    }

                    public init(from decoder: inout Persistence.BinaryDecoder) throws(Persistence.BinaryDecodingError) {
                        var map = try decoder.decodeMap()
                        self.query = try map.decode(forKey: "query")
                        self.ratio = try map.decode(forKey: "ratio")
                        self.page = try map.decode(forKey: "page")
                    }
                }
                """#,
            macroSpecs: [
                "Event": MacroSpec(type: EventMacro.self, conformances: ["Event", "BinaryCodable"]),
                "Constrained": MacroSpec(type: ConstrainedMacro.self),
            ],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test("@Constrained adds no declarations of its own")
    func peerAddsNothing() {
        assertMacroExpansion(
            """
            @Event
            struct Searched {
                @Constrained(.minLength(1))
                var query: String
            }
            """,
            expandedSource: """
                @Event
                struct Searched {
                    var query: String
                }
                """,
            macroSpecs: ["Constrained": MacroSpec(type: ConstrainedMacro.self)],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test("@Constrained on anything but a stored instance property of an @Event struct is an error at the attribute", arguments: [
        "@Event struct S { @Constrained(.minLength(1)) static var a: String = \"\" }",
        "@Event struct S { @Constrained(.minLength(1)) var a: String { \"\" } }",
        "struct S { @Constrained(.minLength(1)) var a: String }",
        "@Event struct S { @Constrained(.minLength(1)) func a() {} }",
    ])
    func misplaced(source: String) {
        let attribute = "@Constrained(.minLength(1)) "
        // The expansion formatter breaks the line before the struct's closing brace.
        let expanded = String(source.replacingFirst(attribute, with: "").dropLast()) + "\n}"
        let attributeColumn = source.columnOf(attribute)

        assertMacroExpansion(
            source,
            expandedSource: expanded,
            diagnostics: [DiagnosticSpec(message: "@Constrained applies only to a stored instance property of an @Event struct", line: 1, column: attributeColumn)],
            macroSpecs: ["Constrained": MacroSpec(type: ConstrainedMacro.self)],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test("A keyword @Event can't read, or no value can satisfy, is an error at its argument, and the struct gets no extension", arguments: [
        (".minLength(n)", "@Constrained's minLength must be a non-negative integer literal"),
        (".maxItems(-1)", "@Constrained's maxItems must be a non-negative integer literal"),
        (".minLength(length: 1)", "@Constrained's minLength must be a non-negative integer literal"),
        (".pattern(\"a\", matching: \"a\")", "@Constrained's pattern and its example must be string literals without interpolation"),
        (".minimum(bound)", "@Constrained's minimum must be a number literal"),
        (".maximum(\"1\")", "@Constrained's maximum must be a number literal"),
        (".pattern(text, example: \"a\")", "@Constrained's pattern and its example must be string literals without interpolation"),
        (".pattern(\"a\")", "@Constrained's pattern and its example must be string literals without interpolation"),
        (".pattern(\"(\", example: \"(\")", "@Constrained's pattern ( isn't a valid regular expression"),
        (".pattern(\"^[0-9]+$\", example: \"abc\")", "@Constrained's example \"abc\" breaks .pattern(\"^[0-9]+$\", example: \"abc\"); give an example every constraint on the property accepts"),
        ("PropertyConstraint.minLength(1)", "@Constrained takes keywords written out, such as .minLength(1), .minimum(0) or .pattern(\"^[a-z]+$\", example: \"abc\")"),
        (".exclusiveMinimum(1)", "@Constrained takes keywords written out, such as .minLength(1), .minimum(0) or .pattern(\"^[a-z]+$\", example: \"abc\")"),
        ("limit", "@Constrained takes keywords written out, such as .minLength(1), .minimum(0) or .pattern(\"^[a-z]+$\", example: \"abc\")"),
    ])
    func unreadable(argument: String, message: String) {
        assertMacroExpansion(
            """
            @Event
            struct Searched {
                @Constrained(\(argument))
                var query: String
            }
            """,
            expandedSource: """
                struct Searched {
                    @Constrained(\(argument))
                    var query: String
                }
                """,
            diagnostics: [DiagnosticSpec(message: message, line: 3, column: 18)],
            macroSpecs: ["Event": MacroSpec(type: EventMacro.self, conformances: ["Event", "BinaryCodable"])],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test("A lower bound above its upper bound is an error at the later of the two", arguments: [
        (".minLength(5), .maxLength(4)", "@Constrained's .minLength(5) and .maxLength(4) leave no value that satisfies both"),
        (".maximum(-2), .minimum(-1.5)", "@Constrained's .maximum(-2) and .minimum(-1.5) leave no value that satisfies both"),
        (".minItems(3), .maxItems(2)", "@Constrained's .minItems(3) and .maxItems(2) leave no value that satisfies both"),
    ])
    func unsatisfiable(arguments: String, message: String) {
        let column = 18 + arguments.columnOf(", ") + 1
        assertMacroExpansion(
            """
            @Event
            struct Searched {
                @Constrained(\(arguments))
                var query: String
            }
            """,
            expandedSource: """
                struct Searched {
                    @Constrained(\(arguments))
                    var query: String
                }
                """,
            diagnostics: [DiagnosticSpec(message: message, line: 3, column: column)],
            macroSpecs: ["Event": MacroSpec(type: EventMacro.self, conformances: ["Event", "BinaryCodable"])],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test("Equal bounds, and a bound with no partner, are satisfiable")
    func satisfiableBounds() {
        assertMacroExpansion(
            """
            @Event
            struct Searched {
                @Constrained(.minLength(3), .maxLength(3), .minimum(1), .maxItems(0))
                var query: String
            }
            """,
            expandedSource: """
                struct Searched {
                    @Constrained(.minLength(3), .maxLength(3), .minimum(1), .maxItems(0))
                    var query: String
                }

                extension Searched {
                    static var schema: Events.EventSchema {
                        Events.EventSchema(name: Self.name, version: 1, consentCategory: Self.consentCategory, properties: [
                            Events.EventSchema.Property(name: "query", typeName: "String", isOptional: false, keywords: Events.ValidationKeyword.keywords(of: \\Self.query) + ([.minLength(3), .maxLength(3), .minimum(1), .maxItems(0)] as [Events.Constraint<String>]).map(\\.keyword)),
                        ])
                    }

                    func constraintViolation() -> Events.ConstraintViolation? {
                        for constraint: Events.Constraint<String> in [.minLength(3), .maxLength(3), .minimum(1), .maxItems(0)] where !constraint.isSatisfied(by: self.query) {
                            return Events.ConstraintViolation(property: "query", keyword: constraint.keyword)
                        }
                        return nil
                    }

                    private static func requireBinaryCodable(query: KeyPath<Self, some Persistence.BinaryCodable>) {
                    }

                    private static var binaryCodableRequirements: Void {
                        requireBinaryCodable(query: \\.query)
                    }

                    func encode(to encoder: inout Persistence.BinaryEncoder) {
                        encoder.encodeMap { map in
                            map.encode(self.query, forKey: "query")
                        }
                    }

                    init(from decoder: inout Persistence.BinaryDecoder) throws(Persistence.BinaryDecodingError) {
                        var map = try decoder.decodeMap()
                        self.query = try map.decode(forKey: "query")
                    }
                }
                """,
            macroSpecs: ["Event": MacroSpec(type: EventMacro.self)],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test("A pattern's example must satisfy the property's other string keywords too")
    func exampleAgainstLengths() {
        assertMacroExpansion(
            """
            @Event
            struct Searched {
                @Constrained(.maxLength(2), .pattern("^[a-z]+$", example: "abc"))
                var query: String
            }
            """,
            expandedSource: """
                struct Searched {
                    @Constrained(.maxLength(2), .pattern("^[a-z]+$", example: "abc"))
                    var query: String
                }
                """,
            diagnostics: [DiagnosticSpec(
                message: #"@Constrained's example "abc" breaks .maxLength(2); give an example every constraint on the property accepts"#,
                line: 3, column: 33
            )],
            macroSpecs: ["Event": MacroSpec(type: EventMacro.self, conformances: ["Event", "BinaryCodable"])],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test("A qualified @EventMacros.Constrained is read too, and a raw string pattern keeps its backslashes")
    func qualifiedAndRaw() {
        assertMacroExpansion(
            ##"""
            @Event
            struct Searched {
                @EventMacros.Constrained(.pattern(#"^\d+$"#, example: "12"))
                var query: String
            }
            """##,
            expandedSource: ##"""
                struct Searched {
                    @EventMacros.Constrained(.pattern(#"^\d+$"#, example: "12"))
                    var query: String
                }

                extension Searched {
                    static var schema: Events.EventSchema {
                        Events.EventSchema(name: Self.name, version: 1, consentCategory: Self.consentCategory, properties: [
                            Events.EventSchema.Property(name: "query", typeName: "String", isOptional: false, keywords: Events.ValidationKeyword.keywords(of: \Self.query) + ([.pattern(#"^\d+$"#, example: "12")] as [Events.Constraint<String>]).map(\.keyword)),
                        ])
                    }

                    func constraintViolation() -> Events.ConstraintViolation? {
                        for constraint: Events.Constraint<String> in [.pattern(#"^\d+$"#, example: "12")] where !constraint.isSatisfied(by: self.query) {
                            return Events.ConstraintViolation(property: "query", keyword: constraint.keyword)
                        }
                        return nil
                    }

                    private static func requireBinaryCodable(query: KeyPath<Self, some Persistence.BinaryCodable>) {
                    }

                    private static var binaryCodableRequirements: Void {
                        requireBinaryCodable(query: \.query)
                    }

                    func encode(to encoder: inout Persistence.BinaryEncoder) {
                        encoder.encodeMap { map in
                            map.encode(self.query, forKey: "query")
                        }
                    }

                    init(from decoder: inout Persistence.BinaryDecoder) throws(Persistence.BinaryDecodingError) {
                        var map = try decoder.decodeMap()
                        self.query = try map.decode(forKey: "query")
                    }
                }
                """##,
            macroSpecs: ["Event": MacroSpec(type: EventMacro.self)],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }
}

extension String {
    /// The 1-based column, in UTF-8 bytes, where `part` first starts, or past the end when it
    /// isn't there.
    fileprivate func columnOf(_ part: String) -> Int {
        let bytes = Array(utf8)
        let target = Array(part.utf8)
        for start in 0 ... Swift.max(0, bytes.count - target.count) where Array(bytes[start ..< Swift.min(bytes.count, start + target.count)]) == target {
            return start + 1
        }
        return bytes.count + 1
    }

    /// The string with the first `part` removed for `replacement`.
    fileprivate func replacingFirst(_ part: String, with replacement: String) -> String {
        let column = columnOf(part)
        guard column <= utf8.count else { return self }
        let bytes = Array(utf8)
        return String(decoding: bytes[..<(column - 1)] + Array(replacement.utf8) + bytes[(column - 1 + part.utf8.count)...], as: UTF8.self)
    }
}
