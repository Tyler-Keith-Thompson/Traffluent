// The @Event macro's expansions, pinned. Each test is self-contained.

import EventMacrosPlugin
import SwiftSyntax
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacros
import SwiftSyntaxMacrosGenericTestSupport
import Testing

@Suite("@Event expansions")
struct EventMacroExpansionTests {
    @Test("A struct gets Event, BinaryCodable, a schema, a requirement per property and its encoding, a map of each property under its name, in declaration order")
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
                        Events.EventSchema(name: Self.name, version: Self.schemaVersion, consentCategory: Self.consentCategory, properties: [
                            Events.EventSchema.Property(name: "plan", typeName: "String", isOptional: false, keywords: Events.ValidationKeyword.keywords(of: \\Self.plan)),
                            Events.EventSchema.Property(name: "seats", typeName: "Int", isOptional: true, keywords: Events.ValidationKeyword.keywords(of: \\Self.seats)),
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
                        encoder.encodeMap { map in
                            map.encode(self.plan, forKey: "plan")
                            map.encode(self.seats, forKey: "seats")
                        }
                    }

                    init(from decoder: inout Persistence.BinaryDecoder) throws(Persistence.BinaryDecodingError) {
                        var map = try decoder.decodeMap()
                        self.plan = try map.decode(forKey: "plan")
                        self.seats = try map.decode(forKey: "seats")
                    }
                }
                """,
            macroSpecs: ["Event": MacroSpec(type: EventMacro.self, conformances: ["Event", "BinaryCodable"])],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test("A property with an initial value is marked in the schema and read with its own value as the default when its key is missing")
    func defaultValue() {
        assertMacroExpansion(
            """
            @Event
            public struct CartViewed {
                public var currency: String = "USD"
                public var coupon: String? = nil
            }
            """,
            expandedSource: """
                public struct CartViewed {
                    public var currency: String = "USD"
                    public var coupon: String? = nil
                }

                extension CartViewed: Events.Event, Persistence.BinaryCodable {
                    public static var schema: Events.EventSchema {
                        Events.EventSchema(name: Self.name, version: Self.schemaVersion, consentCategory: Self.consentCategory, properties: [
                            Events.EventSchema.Property(name: "currency", typeName: "String", isOptional: false, hasDefaultValue: true, keywords: Events.ValidationKeyword.keywords(of: \\Self.currency)),
                            Events.EventSchema.Property(name: "coupon", typeName: "String", isOptional: true, hasDefaultValue: true, keywords: Events.ValidationKeyword.keywords(of: \\Self.coupon)),
                        ])
                    }

                    private static func requireBinaryCodable(currency: KeyPath<Self, some Persistence.BinaryCodable>) {
                    }

                    private static func requireBinaryCodable(coupon: KeyPath<Self, some Persistence.BinaryCodable>) {
                    }

                    private static var binaryCodableRequirements: Void {
                        requireBinaryCodable(currency: \\.currency)
                        requireBinaryCodable(coupon: \\.coupon)
                    }

                    public func encode(to encoder: inout Persistence.BinaryEncoder) {
                        encoder.encodeMap { map in
                            map.encode(self.currency, forKey: "currency")
                            map.encode(self.coupon, forKey: "coupon")
                        }
                    }

                    public init(from decoder: inout Persistence.BinaryDecoder) throws(Persistence.BinaryDecodingError) {
                        var map = try decoder.decodeMap()
                        self.currency = try map.decode(forKey: "currency", default: self.currency)
                        self.coupon = try map.decode(forKey: "coupon", default: self.coupon)
                    }
                }
                """,
            macroSpecs: ["Event": MacroSpec(type: EventMacro.self, conformances: ["Event", "BinaryCodable"])],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test("A name, a consent category and a version become the event's name, consentCategory and schemaVersion, which its schema reads")
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

                    static var schemaVersion: Int {
                        2
                    }

                    static var schema: Events.EventSchema {
                        Events.EventSchema(name: Self.name, version: Self.schemaVersion, consentCategory: Self.consentCategory, properties: [
                            Events.EventSchema.Property(name: "campaign", typeName: "String", isOptional: false, keywords: Events.ValidationKeyword.keywords(of: \Self.campaign)),
                        ])
                    }

                    private static func requireBinaryCodable(campaign: KeyPath<Self, some Persistence.BinaryCodable>) {
                    }

                    private static var binaryCodableRequirements: Void {
                        requireBinaryCodable(campaign: \.campaign)
                    }

                    func encode(to encoder: inout Persistence.BinaryEncoder) {
                        encoder.encodeMap { map in
                            map.encode(self.campaign, forKey: "campaign")
                        }
                    }

                    init(from decoder: inout Persistence.BinaryDecoder) throws(Persistence.BinaryDecodingError) {
                        var map = try decoder.decodeMap()
                        self.campaign = try map.decode(forKey: "campaign")
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
                        Events.EventSchema(name: Self.name, version: Self.schemaVersion, consentCategory: Self.consentCategory, properties: [])
                    }

                    func encode(to encoder: inout Persistence.BinaryEncoder) {
                        encoder.encodeMap { _ in
                        }
                    }

                    init(from decoder: inout Persistence.BinaryDecoder) throws(Persistence.BinaryDecodingError) {
                        _ = try decoder.decodeMap()
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
                        Events.EventSchema(name: Self.name, version: Self.schemaVersion, consentCategory: Self.consentCategory, properties: [])
                    }

                    func encode(to encoder: inout Persistence.BinaryEncoder) {
                        encoder.encodeMap { _ in
                        }
                    }

                    init(from decoder: inout Persistence.BinaryDecoder) throws(Persistence.BinaryDecodingError) {
                        _ = try decoder.decodeMap()
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
                        Events.EventSchema(name: Self.name, version: Self.schemaVersion, consentCategory: Self.consentCategory, properties: [])
                    }

                    public func encode(to encoder: inout Persistence.BinaryEncoder) {
                        encoder.encodeMap { _ in
                        }
                    }

                    public init(from decoder: inout Persistence.BinaryDecoder) throws(Persistence.BinaryDecodingError) {
                        _ = try decoder.decodeMap()
                    }
                }

                extension B: Events.Event, Persistence.BinaryCodable {
                    package static var consentCategory: Events.ConsentCategory {
                        .functional
                    }

                    package static var schema: Events.EventSchema {
                        Events.EventSchema(name: Self.name, version: Self.schemaVersion, consentCategory: Self.consentCategory, properties: [])
                    }

                    package func encode(to encoder: inout Persistence.BinaryEncoder) {
                        encoder.encodeMap { _ in
                        }
                    }

                    package init(from decoder: inout Persistence.BinaryDecoder) throws(Persistence.BinaryDecodingError) {
                        _ = try decoder.decodeMap()
                    }
                }
                """,
            macroSpecs: ["Event": MacroSpec(type: EventMacro.self, conformances: ["Event", "BinaryCodable"])],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test("Static and computed properties and a let with an initial value are left out; observed ones and shared annotations are kept, and a var with an initial value is read with it as its default")
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
                        Events.EventSchema(name: Self.name, version: Self.schemaVersion, consentCategory: Self.consentCategory, properties: [
                            Events.EventSchema.Property(name: "assigned", typeName: "Bool", isOptional: false, keywords: Events.ValidationKeyword.keywords(of: \\Self.assigned)),
                            Events.EventSchema.Property(name: "first", typeName: "UInt16", isOptional: false, keywords: Events.ValidationKeyword.keywords(of: \\Self.first)),
                            Events.EventSchema.Property(name: "second", typeName: "UInt16", isOptional: false, keywords: Events.ValidationKeyword.keywords(of: \\Self.second)),
                            Events.EventSchema.Property(name: "observed", typeName: "Int32", isOptional: false, hasDefaultValue: true, keywords: Events.ValidationKeyword.keywords(of: \\Self.observed)),
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
                        encoder.encodeMap { map in
                            map.encode(self.assigned, forKey: "assigned")
                            map.encode(self.first, forKey: "first")
                            map.encode(self.second, forKey: "second")
                            map.encode(self.observed, forKey: "observed")
                        }
                    }

                    init(from decoder: inout Persistence.BinaryDecoder) throws(Persistence.BinaryDecodingError) {
                        var map = try decoder.decodeMap()
                        self.assigned = try map.decode(forKey: "assigned")
                        self.first = try map.decode(forKey: "first")
                        self.second = try map.decode(forKey: "second")
                        self.observed = try map.decode(forKey: "observed", default: self.observed)
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
                        Events.EventSchema(name: Self.name, version: Self.schemaVersion, consentCategory: Self.consentCategory, properties: [
                            Events.EventSchema.Property(name: "a", typeName: "Int", isOptional: true, keywords: Events.ValidationKeyword.keywords(of: \\Self.a)),
                            Events.EventSchema.Property(name: "b", typeName: "Int", isOptional: true, keywords: Events.ValidationKeyword.keywords(of: \\Self.b)),
                            Events.EventSchema.Property(name: "c", typeName: "Int", isOptional: true, keywords: Events.ValidationKeyword.keywords(of: \\Self.c)),
                            Events.EventSchema.Property(name: "d", typeName: "Int", isOptional: true, keywords: Events.ValidationKeyword.keywords(of: \\Self.d)),
                            Events.EventSchema.Property(name: "e", typeName: "[Int?]", isOptional: false, keywords: Events.ValidationKeyword.keywords(of: \\Self.e)),
                            Events.EventSchema.Property(name: "f", typeName: "Mine.Optional<Int>", isOptional: false, keywords: Events.ValidationKeyword.keywords(of: \\Self.f)),
                            Events.EventSchema.Property(name: "g", typeName: "Int?", isOptional: true, keywords: Events.ValidationKeyword.keywords(of: \\Self.g)),
                            Events.EventSchema.Property(name: "h", typeName: "Array<Int>", isOptional: false, keywords: Events.ValidationKeyword.keywords(of: \\Self.h)),
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
                        encoder.encodeMap { map in
                            map.encode(self.a, forKey: "a")
                            map.encode(self.b, forKey: "b")
                            map.encode(self.c, forKey: "c")
                            map.encode(self.d, forKey: "d")
                            map.encode(self.e, forKey: "e")
                            map.encode(self.f, forKey: "f")
                            map.encode(self.g, forKey: "g")
                            map.encode(self.h, forKey: "h")
                        }
                    }

                    init(from decoder: inout Persistence.BinaryDecoder) throws(Persistence.BinaryDecodingError) {
                        var map = try decoder.decodeMap()
                        self.a = try map.decode(forKey: "a")
                        self.b = try map.decode(forKey: "b")
                        self.c = try map.decode(forKey: "c")
                        self.d = try map.decode(forKey: "d")
                        self.e = try map.decode(forKey: "e")
                        self.f = try map.decode(forKey: "f")
                        self.g = try map.decode(forKey: "g")
                        self.h = try map.decode(forKey: "h")
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
                        Events.EventSchema(name: Self.name, version: Self.schemaVersion, consentCategory: Self.consentCategory, properties: [
                            Events.EventSchema.Property(name: "default", typeName: "Int", isOptional: false, keywords: Events.ValidationKeyword.keywords(of: \\Self.`default`)),
                            Events.EventSchema.Property(name: "var", typeName: "Int", isOptional: false, keywords: Events.ValidationKeyword.keywords(of: \\Self.`var`)),
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
                        encoder.encodeMap { map in
                            map.encode(self.`default`, forKey: "default")
                            map.encode(self.`var`, forKey: "var")
                        }
                    }

                    init(from decoder: inout Persistence.BinaryDecoder) throws(Persistence.BinaryDecodingError) {
                        var map = try decoder.decodeMap()
                        self.`default` = try map.decode(forKey: "default")
                        self.`var` = try map.decode(forKey: "var")
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
                        Events.EventSchema(name: Self.name, version: Self.schemaVersion, consentCategory: Self.consentCategory, properties: [])
                    }

                    func encode(to encoder: inout Persistence.BinaryEncoder) {
                        encoder.encodeMap { _ in
                        }
                    }

                    init(from decoder: inout Persistence.BinaryDecoder) throws(Persistence.BinaryDecodingError) {
                        _ = try decoder.decodeMap()
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
                        Events.EventSchema(name: Self.name, version: Self.schemaVersion, consentCategory: Self.consentCategory, properties: [])
                    }

                    func encode(to encoder: inout Persistence.BinaryEncoder) {
                        encoder.encodeMap { _ in
                        }
                    }

                    init(from decoder: inout Persistence.BinaryDecoder) throws(Persistence.BinaryDecodingError) {
                        _ = try decoder.decodeMap()
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
                        Events.EventSchema(name: Self.name, version: Self.schemaVersion, consentCategory: Self.consentCategory, properties: [])
                    }

                    func encode(to encoder: inout Persistence.BinaryEncoder) {
                        encoder.encodeMap { _ in
                        }
                    }

                    init(from decoder: inout Persistence.BinaryDecoder) throws(Persistence.BinaryDecodingError) {
                        _ = try decoder.decodeMap()
                    }
                }
                """,
            macroSpecs: ["Event": MacroSpec(type: EventMacro.self, conformances: ["Event", "BinaryCodable"])],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }
}
