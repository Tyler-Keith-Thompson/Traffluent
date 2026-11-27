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

                extension Searched: Events.Event, Swift.Encodable, Swift.Decodable {
                    public static var schema: Events.EventSchema {
                        Events.EventSchema(name: Self.name, version: Self.schemaVersion, consentCategory: Self.consentCategory, properties: [
                            Events.EventSchema.Property(name: "query", typeName: "String", isOptional: false, hasInvalidConstraint: Events.ValidationKeyword.hasInvalidConstraint(of: \Self.query), keywords: Events.ValidationKeyword.keywords(of: \Self.query) + ([.minLength(1), .maxLength(8)] as [Events.ValidationKeyword])),
                            Events.EventSchema.Property(name: "ratio", typeName: "Double", isOptional: true, hasInvalidConstraint: Events.ValidationKeyword.hasInvalidConstraint(of: \Self.ratio), keywords: Events.ValidationKeyword.keywords(of: \Self.ratio) + ([.minimum(-1.5), .maximum(10)] as [Events.ValidationKeyword])),
                            Events.EventSchema.Property(name: "page", typeName: "Int", isOptional: false, hasInvalidConstraint: Events.ValidationKeyword.hasInvalidConstraint(of: \Self.page), keywords: Events.ValidationKeyword.keywords(of: \Self.page)),
                        ])
                    }

                    public func constraintViolation() -> Events.ConstraintViolation? {
                        do throws(Events.InvalidConstraint) {
                            let constraint: Events.Constraint<String> = try .minLength(1)
                            if !constraint.isSatisfied(by: self.query) {
                                return Events.ConstraintViolation(property: "query", keyword: constraint.keyword)
                            }
                        } catch {
                            return Events.ConstraintViolation(property: "query", invalidConstraint: ".minLength(1)", error: error)
                        }
                        do throws(Events.InvalidConstraint) {
                            let constraint: Events.Constraint<String> = try .maxLength(8)
                            if !constraint.isSatisfied(by: self.query) {
                                return Events.ConstraintViolation(property: "query", keyword: constraint.keyword)
                            }
                        } catch {
                            return Events.ConstraintViolation(property: "query", invalidConstraint: ".maxLength(8)", error: error)
                        }
                        if let value = self.ratio {
                            do throws(Events.InvalidConstraint) {
                                let constraint: Events.Constraint<Double> = try .minimum(-1.5)
                                if !constraint.isSatisfied(by: value) {
                                    return Events.ConstraintViolation(property: "ratio", keyword: constraint.keyword)
                                }
                            } catch {
                                return Events.ConstraintViolation(property: "ratio", invalidConstraint: ".minimum(-1.5)", error: error)
                            }
                            do throws(Events.InvalidConstraint) {
                                let constraint: Events.Constraint<Double> = try .maximum(10)
                                if !constraint.isSatisfied(by: value) {
                                    return Events.ConstraintViolation(property: "ratio", keyword: constraint.keyword)
                                }
                            } catch {
                                return Events.ConstraintViolation(property: "ratio", invalidConstraint: ".maximum(10)", error: error)
                            }
                        }
                        return nil
                    }

                    private static func requireCodable(query: KeyPath<Self, some Swift.Codable>) {
                    }

                    private static func requireCodable(ratio: KeyPath<Self, some Swift.Codable>) {
                    }

                    private static func requireCodable(page: KeyPath<Self, some Swift.Codable>) {
                    }

                    private static var codableRequirements: Void {
                        requireCodable(query: \.query)
                        requireCodable(ratio: \.ratio)
                        requireCodable(page: \.page)
                    }

                    private enum CodingKeys: Swift.String, Swift.CodingKey {
                        case query
                        case ratio
                        case page
                    }

                    public func encode(to encoder: any Swift.Encoder) throws {
                        var container = encoder.container(keyedBy: CodingKeys.self)
                        try container.encode(self.query, forKey: .query)
                        try container.encodeIfPresent(self.ratio, forKey: .ratio)
                        try container.encode(self.page, forKey: .page)
                    }

                    public init(from decoder: any Swift.Decoder) throws {
                        let container = try decoder.container(keyedBy: CodingKeys.self)
                        self.query = try container.decode(String.self, forKey: .query)
                        self.ratio = try container.decodeIfPresent(Double.self, forKey: .ratio)
                        self.page = try container.decode(Int.self, forKey: .page)
                    }
                }

                extension Searched {
                    #if objectFormat(MachO)
                    @section("__DATA_CONST,__trfl_events")
                    #elseif objectFormat(ELF)
                    @section("trfl_events")
                    #endif
                    @used
                    private nonisolated static let __discoveryRecord: Events.__EventDiscovery.Record = (0x6576_6E74, 0, { outValue, type, _, _ in
                            Events.__EventDiscovery.load(Searched.self, schema: Searched.schema, into: outValue, ofType: type)
                        }, 0, 0)
                }
                """#,
            macroSpecs: [
                "Event": MacroSpec(type: EventMacro.self, conformances: ["Event", "Encodable", "Decodable"]),
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
            macroSpecs: ["Event": MacroSpec(type: EventMacro.self, conformances: ["Event", "Encodable", "Decodable"])],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test("A bound its property's type can't state as written is an error at the bound", arguments: [
        ("Int", ".maximum(9_007_199_254_740_993)", "@Constrained's .maximum(9_007_199_254_740_993) on Int can't be stated exactly in a schema, whose numbers are Doubles; use a bound of at most 2^53 in magnitude"),
        ("UInt64", ".minimum(18446744073709551615)", "@Constrained's .minimum(18446744073709551615) on UInt64 can't be stated exactly in a schema, whose numbers are Doubles; use a bound of at most 2^53 in magnitude"),
        ("Int64", ".minimum(-9007199254740993)", "@Constrained's .minimum(-9007199254740993) on Int64 can't be stated exactly in a schema, whose numbers are Doubles; use a bound of at most 2^53 in magnitude"),
        ("Float", ".maximum(1e39)", "@Constrained's .maximum(1e39) overflows Float to infinity"),
        ("Double", ".minimum(-1e309)", "@Constrained's .minimum(-1e309) overflows Double to infinity"),
        ("Float", ".maximum(0.1000000001)", "@Constrained's .maximum(0.1000000001) is 0.1 as a Float; write that bound"),
        ("Float", ".minimum(-16777217)", "@Constrained's .minimum(-16777217) is -16777216.0 as a Float; write that bound"),
    ])
    func unstatableBound(type: String, argument: String, message: String) {
        assertMacroExpansion(
            """
            @Event
            struct Measured {
                @Constrained(\(argument))
                var value: \(type)
            }
            """,
            expandedSource: """
                struct Measured {
                    @Constrained(\(argument))
                    var value: \(type)
                }
                """,
            diagnostics: [DiagnosticSpec(message: message, line: 3, column: 18)],
            macroSpecs: ["Event": MacroSpec(type: EventMacro.self, conformances: ["Event", "Encodable", "Decodable"])],
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
            macroSpecs: ["Event": MacroSpec(type: EventMacro.self, conformances: ["Event", "Encodable", "Decodable"])],
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
                        Events.EventSchema(name: Self.name, version: Self.schemaVersion, consentCategory: Self.consentCategory, properties: [
                            Events.EventSchema.Property(name: "query", typeName: "String", isOptional: false, hasInvalidConstraint: Events.ValidationKeyword.hasInvalidConstraint(of: \\Self.query), keywords: Events.ValidationKeyword.keywords(of: \\Self.query) + ([.minLength(3), .maxLength(3), .minimum(1), .maxItems(0)] as [Events.ValidationKeyword])),
                        ])
                    }

                    func constraintViolation() -> Events.ConstraintViolation? {
                        do throws(Events.InvalidConstraint) {
                            let constraint: Events.Constraint<String> = try .minLength(3)
                            if !constraint.isSatisfied(by: self.query) {
                                return Events.ConstraintViolation(property: "query", keyword: constraint.keyword)
                            }
                        } catch {
                            return Events.ConstraintViolation(property: "query", invalidConstraint: ".minLength(3)", error: error)
                        }
                        do throws(Events.InvalidConstraint) {
                            let constraint: Events.Constraint<String> = try .maxLength(3)
                            if !constraint.isSatisfied(by: self.query) {
                                return Events.ConstraintViolation(property: "query", keyword: constraint.keyword)
                            }
                        } catch {
                            return Events.ConstraintViolation(property: "query", invalidConstraint: ".maxLength(3)", error: error)
                        }
                        do throws(Events.InvalidConstraint) {
                            let constraint: Events.Constraint<String> = try .minimum(1)
                            if !constraint.isSatisfied(by: self.query) {
                                return Events.ConstraintViolation(property: "query", keyword: constraint.keyword)
                            }
                        } catch {
                            return Events.ConstraintViolation(property: "query", invalidConstraint: ".minimum(1)", error: error)
                        }
                        do throws(Events.InvalidConstraint) {
                            let constraint: Events.Constraint<String> = try .maxItems(0)
                            if !constraint.isSatisfied(by: self.query) {
                                return Events.ConstraintViolation(property: "query", keyword: constraint.keyword)
                            }
                        } catch {
                            return Events.ConstraintViolation(property: "query", invalidConstraint: ".maxItems(0)", error: error)
                        }
                        return nil
                    }

                    private static func requireCodable(query: KeyPath<Self, some Swift.Codable>) {
                    }

                    private static var codableRequirements: Void {
                        requireCodable(query: \\.query)
                    }

                    private enum CodingKeys: Swift.String, Swift.CodingKey {
                        case query
                    }

                    func encode(to encoder: any Swift.Encoder) throws {
                        var container = encoder.container(keyedBy: CodingKeys.self)
                        try container.encode(self.query, forKey: .query)
                    }

                    init(from decoder: any Swift.Decoder) throws {
                        let container = try decoder.container(keyedBy: CodingKeys.self)
                        self.query = try container.decode(String.self, forKey: .query)
                    }
                }

                extension Searched {
                    #if objectFormat(MachO)
                    @section("__DATA_CONST,__trfl_events")
                    #elseif objectFormat(ELF)
                    @section("trfl_events")
                    #endif
                    @used
                    private nonisolated static let __discoveryRecord: Events.__EventDiscovery.Record = (0x6576_6E74, 0, { outValue, type, _, _ in
                            Events.__EventDiscovery.load(Searched.self, schema: Searched.schema, into: outValue, ofType: type)
                        }, 0, 0)
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
            macroSpecs: ["Event": MacroSpec(type: EventMacro.self, conformances: ["Event", "Encodable", "Decodable"])],
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
                        Events.EventSchema(name: Self.name, version: Self.schemaVersion, consentCategory: Self.consentCategory, properties: [
                            Events.EventSchema.Property(name: "query", typeName: "String", isOptional: false, hasInvalidConstraint: Events.ValidationKeyword.hasInvalidConstraint(of: \Self.query), keywords: Events.ValidationKeyword.keywords(of: \Self.query) + ([.pattern(#"^\d+$"#, example: "12")] as [Events.ValidationKeyword])),
                        ])
                    }

                    func constraintViolation() -> Events.ConstraintViolation? {
                        do throws(Events.InvalidConstraint) {
                            let constraint: Events.Constraint<String> = try .pattern(#"^\d+$"#, example: "12")
                            if !constraint.isSatisfied(by: self.query) {
                                return Events.ConstraintViolation(property: "query", keyword: constraint.keyword)
                            }
                        } catch {
                            return Events.ConstraintViolation(property: "query", invalidConstraint: ".pattern(#\"^\\d+$\"#, example: \"12\")", error: error)
                        }
                        return nil
                    }

                    private static func requireCodable(query: KeyPath<Self, some Swift.Codable>) {
                    }

                    private static var codableRequirements: Void {
                        requireCodable(query: \.query)
                    }

                    private enum CodingKeys: Swift.String, Swift.CodingKey {
                        case query
                    }

                    func encode(to encoder: any Swift.Encoder) throws {
                        var container = encoder.container(keyedBy: CodingKeys.self)
                        try container.encode(self.query, forKey: .query)
                    }

                    init(from decoder: any Swift.Decoder) throws {
                        let container = try decoder.container(keyedBy: CodingKeys.self)
                        self.query = try container.decode(String.self, forKey: .query)
                    }
                }

                extension Searched {
                    #if objectFormat(MachO)
                    @section("__DATA_CONST,__trfl_events")
                    #elseif objectFormat(ELF)
                    @section("trfl_events")
                    #endif
                    @used
                    private nonisolated static let __discoveryRecord: Events.__EventDiscovery.Record = (0x6576_6E74, 0, { outValue, type, _, _ in
                            Events.__EventDiscovery.load(Searched.self, schema: Searched.schema, into: outValue, ofType: type)
                        }, 0, 0)
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
