// The @Event macro's expansions, pinned. Each test is self-contained.

import EventMacrosPlugin
import SwiftSyntax
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacros
import SwiftSyntaxMacrosGenericTestSupport
import Testing

@Suite("@Event expansions")
struct EventMacroExpansionTests {
    @Test("A struct gets Event, BinaryCodable, a schema, a requirement per property and its encoding in declaration order")
    func structure() {
        assertMacroExpansion(
            """
            @Event
            struct SignedUp {
                var plan: String
                var seats: Int?
            }
            """,
            expandedSource: """
                struct SignedUp {
                    var plan: String
                    var seats: Int?
                }

                extension SignedUp: Events.Event, Persistence.BinaryCodable {
                    static var schema: Events.EventSchema {
                        Events.EventSchema(name: Self.name, version: 1, consentCategory: Self.consentCategory, properties: [
                            Events.EventSchema.Property(name: "plan", typeName: "String", isOptional: false),
                            Events.EventSchema.Property(name: "seats", typeName: "Int", isOptional: true),
                        ])
                    }

                    private static func requireBinaryCodable(plan: KeyPath<Self, some Persistence.BinaryCodable>) {
                    }

                    private static func requireBinaryCodable(seats: KeyPath<Self, some Persistence.BinaryCodable>) {
                    }

                    private static var binaryCodableRequirements: Void {
                        requireBinaryCodable(plan: \\.plan)
                        requireBinaryCodable(seats: \\.seats)
                    }

                    func encode(to encoder: inout Persistence.BinaryEncoder) {
                        encoder.encode(self.plan)
                        encoder.encode(self.seats)
                    }

                    init(from decoder: inout Persistence.BinaryDecoder) throws(Persistence.BinaryDecodingError) {
                        self.plan = try decoder.decode()
                        self.seats = try decoder.decode()
                    }
                }
                """,
            macroSpecs: ["Event": MacroSpec(type: EventMacro.self, conformances: ["Event", "BinaryCodable"])],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test("A name, a consent category and a version become the event's name, consentCategory and schema version")
    func arguments() {
        assertMacroExpansion(
            #"""
            @Event(name: "ad_clicked", consent: .advertising, version: 2)
            struct AdClicked {
                var campaign: String
            }
            """#,
            expandedSource: #"""
                struct AdClicked {
                    var campaign: String
                }

                extension AdClicked: Events.Event, Persistence.BinaryCodable {
                    static var name: String {
                        "ad_clicked"
                    }

                    static var consentCategory: Events.ConsentCategory {
                        .advertising
                    }

                    static var schema: Events.EventSchema {
                        Events.EventSchema(name: Self.name, version: 2, consentCategory: Self.consentCategory, properties: [
                            Events.EventSchema.Property(name: "campaign", typeName: "String", isOptional: false),
                        ])
                    }

                    private static func requireBinaryCodable(campaign: KeyPath<Self, some Persistence.BinaryCodable>) {
                    }

                    private static var binaryCodableRequirements: Void {
                        requireBinaryCodable(campaign: \.campaign)
                    }

                    func encode(to encoder: inout Persistence.BinaryEncoder) {
                        encoder.encode(self.campaign)
                    }

                    init(from decoder: inout Persistence.BinaryDecoder) throws(Persistence.BinaryDecodingError) {
                        self.campaign = try decoder.decode()
                    }
                }
                """#,
            macroSpecs: ["Event": MacroSpec(type: EventMacro.self, conformances: ["Event", "BinaryCodable"])],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test("nil for the name or the consent category keeps the default, as leaving it out does")
    func nilArguments() {
        assertMacroExpansion(
            """
            @Event(name: nil, consent: nil)
            struct Opened {
            }
            """,
            expandedSource: """
                struct Opened {
                }

                extension Opened: Events.Event, Persistence.BinaryCodable {
                    static var schema: Events.EventSchema {
                        Events.EventSchema(name: Self.name, version: 1, consentCategory: Self.consentCategory, properties: [])
                    }

                    func encode(to encoder: inout Persistence.BinaryEncoder) {
                    }

                    init(from decoder: inout Persistence.BinaryDecoder) throws(Persistence.BinaryDecodingError) {
                    }
                }
                """,
            macroSpecs: ["Event": MacroSpec(type: EventMacro.self, conformances: ["Event", "BinaryCodable"])],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test("A raw string literal name and a custom consent category are copied as written")
    func literalsAsWritten() {
        assertMacroExpansion(
            ##"""
            @Event(name: #"crash"#, consent: ConsentCategory("crash-reports"))
            struct Crashed {
            }
            """##,
            expandedSource: ##"""
                struct Crashed {
                }

                extension Crashed: Events.Event, Persistence.BinaryCodable {
                    static var name: String {
                        #"crash"#
                    }

                    static var consentCategory: Events.ConsentCategory {
                        ConsentCategory("crash-reports")
                    }

                    static var schema: Events.EventSchema {
                        Events.EventSchema(name: Self.name, version: 1, consentCategory: Self.consentCategory, properties: [])
                    }

                    func encode(to encoder: inout Persistence.BinaryEncoder) {
                    }

                    init(from decoder: inout Persistence.BinaryDecoder) throws(Persistence.BinaryDecodingError) {
                    }
                }
                """##,
            macroSpecs: ["Event": MacroSpec(type: EventMacro.self, conformances: ["Event", "BinaryCodable"])],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test("A public or package struct's generated members take its access level")
    func accessLevels() {
        assertMacroExpansion(
            """
            @Event(name: "a")
            public struct A {
            }
            @Event(consent: .functional)
            package struct B {
            }
            """,
            expandedSource: """
                public struct A {
                }
                package struct B {
                }

                extension A: Events.Event, Persistence.BinaryCodable {
                    public static var name: String {
                        "a"
                    }

                    public static var schema: Events.EventSchema {
                        Events.EventSchema(name: Self.name, version: 1, consentCategory: Self.consentCategory, properties: [])
                    }

                    public func encode(to encoder: inout Persistence.BinaryEncoder) {
                    }

                    public init(from decoder: inout Persistence.BinaryDecoder) throws(Persistence.BinaryDecodingError) {
                    }
                }

                extension B: Events.Event, Persistence.BinaryCodable {
                    package static var consentCategory: Events.ConsentCategory {
                        .functional
                    }

                    package static var schema: Events.EventSchema {
                        Events.EventSchema(name: Self.name, version: 1, consentCategory: Self.consentCategory, properties: [])
                    }

                    package func encode(to encoder: inout Persistence.BinaryEncoder) {
                    }

                    package init(from decoder: inout Persistence.BinaryDecoder) throws(Persistence.BinaryDecodingError) {
                    }
                }
                """,
            macroSpecs: ["Event": MacroSpec(type: EventMacro.self, conformances: ["Event", "BinaryCodable"])],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test("Static and computed properties and a let with an initial value are left out; observed ones and shared annotations are kept")
    func storedPropertiesOnly() {
        assertMacroExpansion(
            """
            @Event
            struct Shapes {
                static let shared = 1
                static var lastScreen: String = ""
                var doubled: Int { 2 }
                var read: Int {
                    get { 3 }
                }
                let fixed = 7
                let assigned: Bool
                var first, second: UInt16
                var observed: Int32 = 0 {
                    willSet {}
                    didSet {}
                }
            }
            """,
            expandedSource: """
                struct Shapes {
                    static let shared = 1
                    static var lastScreen: String = ""
                    var doubled: Int { 2 }
                    var read: Int {
                        get { 3 }
                    }
                    let fixed = 7
                    let assigned: Bool
                    var first, second: UInt16
                    var observed: Int32 = 0 {
                        willSet {}
                        didSet {}
                    }
                }

                extension Shapes: Events.Event, Persistence.BinaryCodable {
                    static var schema: Events.EventSchema {
                        Events.EventSchema(name: Self.name, version: 1, consentCategory: Self.consentCategory, properties: [
                            Events.EventSchema.Property(name: "assigned", typeName: "Bool", isOptional: false),
                            Events.EventSchema.Property(name: "first", typeName: "UInt16", isOptional: false),
                            Events.EventSchema.Property(name: "second", typeName: "UInt16", isOptional: false),
                            Events.EventSchema.Property(name: "observed", typeName: "Int32", isOptional: false),
                        ])
                    }

                    private static func requireBinaryCodable(assigned: KeyPath<Self, some Persistence.BinaryCodable>) {
                    }

                    private static func requireBinaryCodable(first: KeyPath<Self, some Persistence.BinaryCodable>) {
                    }

                    private static func requireBinaryCodable(second: KeyPath<Self, some Persistence.BinaryCodable>) {
                    }

                    private static func requireBinaryCodable(observed: KeyPath<Self, some Persistence.BinaryCodable>) {
                    }

                    private static var binaryCodableRequirements: Void {
                        requireBinaryCodable(assigned: \\.assigned)
                        requireBinaryCodable(first: \\.first)
                        requireBinaryCodable(second: \\.second)
                        requireBinaryCodable(observed: \\.observed)
                    }

                    func encode(to encoder: inout Persistence.BinaryEncoder) {
                        encoder.encode(self.assigned)
                        encoder.encode(self.first)
                        encoder.encode(self.second)
                        encoder.encode(self.observed)
                    }

                    init(from decoder: inout Persistence.BinaryDecoder) throws(Persistence.BinaryDecodingError) {
                        self.assigned = try decoder.decode()
                        self.first = try decoder.decode()
                        self.second = try decoder.decode()
                        self.observed = try decoder.decode()
                    }
                }
                """,
            macroSpecs: ["Event": MacroSpec(type: EventMacro.self, conformances: ["Event", "BinaryCodable"])],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test("Every spelling of an optional is optional in the schema, with the wrapped type's name; a type that only mentions Optional, or another generic type, isn't")
    func optionals() {
        assertMacroExpansion(
            """
            @Event
            struct Spellings {
                var a: Int?
                var b: Int!
                var c: Optional<Int>
                var d: Swift.Optional<Int>
                var e: [Int?]
                var f: Mine.Optional<Int>
                var g: Int??
                var h: Array<Int>
            }
            """,
            expandedSource: """
                struct Spellings {
                    var a: Int?
                    var b: Int!
                    var c: Optional<Int>
                    var d: Swift.Optional<Int>
                    var e: [Int?]
                    var f: Mine.Optional<Int>
                    var g: Int??
                    var h: Array<Int>
                }

                extension Spellings: Events.Event, Persistence.BinaryCodable {
                    static var schema: Events.EventSchema {
                        Events.EventSchema(name: Self.name, version: 1, consentCategory: Self.consentCategory, properties: [
                            Events.EventSchema.Property(name: "a", typeName: "Int", isOptional: true),
                            Events.EventSchema.Property(name: "b", typeName: "Int", isOptional: true),
                            Events.EventSchema.Property(name: "c", typeName: "Int", isOptional: true),
                            Events.EventSchema.Property(name: "d", typeName: "Int", isOptional: true),
                            Events.EventSchema.Property(name: "e", typeName: "[Int?]", isOptional: false),
                            Events.EventSchema.Property(name: "f", typeName: "Mine.Optional<Int>", isOptional: false),
                            Events.EventSchema.Property(name: "g", typeName: "Int?", isOptional: true),
                            Events.EventSchema.Property(name: "h", typeName: "Array<Int>", isOptional: false),
                        ])
                    }

                    private static func requireBinaryCodable(a: KeyPath<Self, some Persistence.BinaryCodable>) {
                    }

                    private static func requireBinaryCodable(b: KeyPath<Self, some Persistence.BinaryCodable>) {
                    }

                    private static func requireBinaryCodable(c: KeyPath<Self, some Persistence.BinaryCodable>) {
                    }

                    private static func requireBinaryCodable(d: KeyPath<Self, some Persistence.BinaryCodable>) {
                    }

                    private static func requireBinaryCodable(e: KeyPath<Self, some Persistence.BinaryCodable>) {
                    }

                    private static func requireBinaryCodable(f: KeyPath<Self, some Persistence.BinaryCodable>) {
                    }

                    private static func requireBinaryCodable(g: KeyPath<Self, some Persistence.BinaryCodable>) {
                    }

                    private static func requireBinaryCodable(h: KeyPath<Self, some Persistence.BinaryCodable>) {
                    }

                    private static var binaryCodableRequirements: Void {
                        requireBinaryCodable(a: \\.a)
                        requireBinaryCodable(b: \\.b)
                        requireBinaryCodable(c: \\.c)
                        requireBinaryCodable(d: \\.d)
                        requireBinaryCodable(e: \\.e)
                        requireBinaryCodable(f: \\.f)
                        requireBinaryCodable(g: \\.g)
                        requireBinaryCodable(h: \\.h)
                    }

                    func encode(to encoder: inout Persistence.BinaryEncoder) {
                        encoder.encode(self.a)
                        encoder.encode(self.b)
                        encoder.encode(self.c)
                        encoder.encode(self.d)
                        encoder.encode(self.e)
                        encoder.encode(self.f)
                        encoder.encode(self.g)
                        encoder.encode(self.h)
                    }

                    init(from decoder: inout Persistence.BinaryDecoder) throws(Persistence.BinaryDecodingError) {
                        self.a = try decoder.decode()
                        self.b = try decoder.decode()
                        self.c = try decoder.decode()
                        self.d = try decoder.decode()
                        self.e = try decoder.decode()
                        self.f = try decoder.decode()
                        self.g = try decoder.decode()
                        self.h = try decoder.decode()
                    }
                }
                """,
            macroSpecs: ["Event": MacroSpec(type: EventMacro.self, conformances: ["Event", "BinaryCodable"])],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test("A backticked name is bare in the schema and in a label, but keeps its backticks where a label needs them")
    func backticks() {
        assertMacroExpansion(
            """
            @Event
            struct Keywords {
                var `default`: Int
                var `var`: Int
            }
            """,
            expandedSource: """
                struct Keywords {
                    var `default`: Int
                    var `var`: Int
                }

                extension Keywords: Events.Event, Persistence.BinaryCodable {
                    static var schema: Events.EventSchema {
                        Events.EventSchema(name: Self.name, version: 1, consentCategory: Self.consentCategory, properties: [
                            Events.EventSchema.Property(name: "default", typeName: "Int", isOptional: false),
                            Events.EventSchema.Property(name: "var", typeName: "Int", isOptional: false),
                        ])
                    }

                    private static func requireBinaryCodable(default: KeyPath<Self, some Persistence.BinaryCodable>) {
                    }

                    private static func requireBinaryCodable(`var`: KeyPath<Self, some Persistence.BinaryCodable>) {
                    }

                    private static var binaryCodableRequirements: Void {
                        requireBinaryCodable(default: \\.`default`)
                        requireBinaryCodable(`var`: \\.`var`)
                    }

                    func encode(to encoder: inout Persistence.BinaryEncoder) {
                        encoder.encode(self.`default`)
                        encoder.encode(self.`var`)
                    }

                    init(from decoder: inout Persistence.BinaryDecoder) throws(Persistence.BinaryDecodingError) {
                        self.`default` = try decoder.decode()
                        self.`var` = try decoder.decode()
                    }
                }
                """,
            macroSpecs: ["Event": MacroSpec(type: EventMacro.self, conformances: ["Event", "BinaryCodable"])],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test("Only the conformances the compiler asks for are added: those the struct lacks, by any spelling")
    func requestedConformance() {
        assertMacroExpansion(
            """
            @Event
            struct Opened: Event {
            }
            """,
            expandedSource: """
                struct Opened: Event {
                }

                extension Opened: Persistence.BinaryCodable {
                    static var schema: Events.EventSchema {
                        Events.EventSchema(name: Self.name, version: 1, consentCategory: Self.consentCategory, properties: [])
                    }

                    func encode(to encoder: inout Persistence.BinaryEncoder) {
                    }

                    init(from decoder: inout Persistence.BinaryDecoder) throws(Persistence.BinaryDecodingError) {
                    }
                }
                """,
            macroSpecs: ["Event": MacroSpec(type: EventMacro.self, conformances: ["Persistence.BinaryCodable"])],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test("A struct that already has both conformances gets their members alone")
    func noConformances() {
        assertMacroExpansion(
            """
            @Event
            struct Closed: Event, BinaryCodable {
            }
            """,
            expandedSource: """
                struct Closed: Event, BinaryCodable {
                }

                extension Closed {
                    static var schema: Events.EventSchema {
                        Events.EventSchema(name: Self.name, version: 1, consentCategory: Self.consentCategory, properties: [])
                    }

                    func encode(to encoder: inout Persistence.BinaryEncoder) {
                    }

                    init(from decoder: inout Persistence.BinaryDecoder) throws(Persistence.BinaryDecodingError) {
                    }
                }
                """,
            macroSpecs: ["Event": MacroSpec(type: EventMacro.self)],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test("A nested struct's extension names it through its enclosing type")
    func nested() {
        assertMacroExpansion(
            """
            enum Checkout {
                @Event
                struct Started {
                }
            }
            """,
            expandedSource: """
                enum Checkout {
                    struct Started {
                    }
                }

                extension Checkout.Started: Events.Event, Persistence.BinaryCodable {
                    static var schema: Events.EventSchema {
                        Events.EventSchema(name: Self.name, version: 1, consentCategory: Self.consentCategory, properties: [])
                    }

                    func encode(to encoder: inout Persistence.BinaryEncoder) {
                    }

                    init(from decoder: inout Persistence.BinaryDecoder) throws(Persistence.BinaryDecodingError) {
                    }
                }
                """,
            macroSpecs: ["Event": MacroSpec(type: EventMacro.self, conformances: ["Event", "BinaryCodable"])],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }
}
