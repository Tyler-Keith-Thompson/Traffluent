// The @Event macro's expansions of raw-value enum properties, pinned: the enumeration each
// property's schema gets, and the error for an enum declared inside the event that isn't Codable.
// Each test is self-contained.
//
// A discovery record is pinned as the one #__eventRecord call the expansion writes, which
// assertMacroExpansion leaves unexpanded as it isn't in the table: the per-format declarations
// behind it are LinkerSets' (LinkerSetRecordMacro), so these tests pin only Traffluent's part, the
// same on every swift-syntax the plugin accepts.

import EventMacrosPlugin
import SwiftSyntax
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacros
import SwiftSyntaxMacrosGenericTestSupport
import Testing

@Suite("@Event expansions: raw-value enums")
struct EventMacroEnumerationExpansionTests {
    @Test("A property of a raw-value enum declared inside the event lists its cases, written out, through an optional, an array, Sensitive and a qualified name")
    func nestedEnum() {
        assertMacroExpansion(
            """
            @Event
            struct CheckoutFailed {
                enum Reason: String, Codable {
                    case paymentDeclined, outOfStock
                    case networkUnavailable = "offline"
                }
                var reason: Reason
                var previous: Reason?
                var history: [Sensitive<CheckoutFailed.Reason>]
            }
            """,
            expandedSource: """
                struct CheckoutFailed {
                    enum Reason: String, Codable {
                        case paymentDeclined, outOfStock
                        case networkUnavailable = "offline"
                    }
                    var reason: Reason
                    var previous: Reason?
                    var history: [Sensitive<CheckoutFailed.Reason>]
                }

                private enum __macro_local_15linkerSetRecordfMu_ {
                    #__eventRecord(kind: 0x65766E74, storing: CheckoutFailed.self as any (Events.__DiscoverableEvent).Type)
                }

                nonisolated extension CheckoutFailed: Events.Event, Swift.Encodable, Swift.Decodable, Events.__DiscoverableEvent {
                    static var schema: Events.EventSchema {
                        Events.EventSchema(name: Self.name, version: Self.schemaVersion, consentCategory: Self.consentCategory, properties: [
                            Events.EventSchema.Property(name: "reason", typeName: "Reason", isOptional: false, hasInvalidConstraint: Events.ValidationKeyword.hasInvalidConstraint(of: \\Self.reason), keywords: Events.ValidationKeyword.keywords(of: \\Self.reason), enumeration: Events.EventSchema.Enumeration(cases: [.`paymentDeclined`, .`outOfStock`, .`networkUnavailable`] as [Self.Reason])),
                            Events.EventSchema.Property(name: "previous", typeName: "Reason", isOptional: true, hasInvalidConstraint: Events.ValidationKeyword.hasInvalidConstraint(of: \\Self.previous), keywords: Events.ValidationKeyword.keywords(of: \\Self.previous), enumeration: Events.EventSchema.Enumeration(cases: [.`paymentDeclined`, .`outOfStock`, .`networkUnavailable`] as [Self.Reason])),
                            Events.EventSchema.Property(name: "history", typeName: "[Sensitive<CheckoutFailed.Reason>]", isOptional: false, hasInvalidConstraint: Events.ValidationKeyword.hasInvalidConstraint(of: \\Self.history), keywords: Events.ValidationKeyword.keywords(of: \\Self.history), enumeration: Events.EventSchema.Enumeration(cases: [.`paymentDeclined`, .`outOfStock`, .`networkUnavailable`] as [Self.Reason])),
                        ])
                    }

                    private static func requireCodable(reason: KeyPath<Self, some Swift.Codable>) {
                    }

                    private static func requireCodable(previous: KeyPath<Self, some Swift.Codable>) {
                    }

                    private static func requireCodable(history: KeyPath<Self, some Swift.Codable>) {
                    }

                    private static var codableRequirements: Void {
                        requireCodable(reason: \\.reason)
                        requireCodable(previous: \\.previous)
                        requireCodable(history: \\.history)
                    }

                    private enum CodingKeys: Swift.String, Swift.CodingKey {
                        case reason
                        case previous
                        case history
                    }

                    func encode(to encoder: any Swift.Encoder) throws {
                        var container = encoder.container(keyedBy: CodingKeys.self)
                        try container.encode(self.reason, forKey: .reason)
                        try container.encodeIfPresent(self.previous, forKey: .previous)
                        try container.encode(self.history, forKey: .history)
                    }

                    init(from decoder: any Swift.Decoder) throws {
                        let container = try decoder.container(keyedBy: CodingKeys.self)
                        self.reason = try Self.decodeValue(from: container, forKey: .reason)
                        self.previous = try Self.decodeIfPresentValue(from: container, forKey: .previous)
                        self.history = try Self.decodeValue(from: container, forKey: .history)
                    }

                    private static func decodeValue<Decoded: Swift.Decodable>(from container: Swift.KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> Decoded {
                        try container.decode(Decoded.self, forKey: key)
                    }

                    private static func decodeIfPresentValue<Decoded: Swift.Decodable>(from container: Swift.KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> Decoded? {
                        try container.decodeIfPresent(Decoded.self, forKey: key)
                    }
                }
                """,
            macroSpecs: ["Event": MacroSpec(type: EventMacro.self, conformances: ["Event", "Encodable", "Decodable", "__DiscoverableEvent"])],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test("The enum is found through Self, Optional<T>, Array<T>, and Swift's, Events' and Traffluent's qualified names")
    func spellings() {
        assertMacroExpansion(
            """
            @Event
            struct Spelled {
                enum Reason: String, Codable {
                    case a
                }
                var own: Self.Reason
                var maybe: Optional<Reason>
                var list: Array<Reason>
                var qualified: Swift.Array<Swift.Optional<Reason>>
                var secret: Events.Sensitive<Reason>
                var umbrella: Traffluent.Sensitive<Reason>
            }
            """,
            expandedSource: """
                struct Spelled {
                    enum Reason: String, Codable {
                        case a
                    }
                    var own: Self.Reason
                    var maybe: Optional<Reason>
                    var list: Array<Reason>
                    var qualified: Swift.Array<Swift.Optional<Reason>>
                    var secret: Events.Sensitive<Reason>
                    var umbrella: Traffluent.Sensitive<Reason>
                }

                private enum __macro_local_15linkerSetRecordfMu_ {
                    #__eventRecord(kind: 0x65766E74, storing: Spelled.self as any (Events.__DiscoverableEvent).Type)
                }

                nonisolated extension Spelled: Events.Event, Swift.Encodable, Swift.Decodable, Events.__DiscoverableEvent {
                    static var schema: Events.EventSchema {
                        Events.EventSchema(name: Self.name, version: Self.schemaVersion, consentCategory: Self.consentCategory, properties: [
                            Events.EventSchema.Property(name: "own", typeName: "Self.Reason", isOptional: false, hasInvalidConstraint: Events.ValidationKeyword.hasInvalidConstraint(of: \\Self.own), keywords: Events.ValidationKeyword.keywords(of: \\Self.own), enumeration: Events.EventSchema.Enumeration(cases: [.`a`] as [Self.Reason])),
                            Events.EventSchema.Property(name: "maybe", typeName: "Reason", isOptional: true, hasInvalidConstraint: Events.ValidationKeyword.hasInvalidConstraint(of: \\Self.maybe), keywords: Events.ValidationKeyword.keywords(of: \\Self.maybe), enumeration: Events.EventSchema.Enumeration(cases: [.`a`] as [Self.Reason])),
                            Events.EventSchema.Property(name: "list", typeName: "Array<Reason>", isOptional: false, hasInvalidConstraint: Events.ValidationKeyword.hasInvalidConstraint(of: \\Self.list), keywords: Events.ValidationKeyword.keywords(of: \\Self.list), enumeration: Events.EventSchema.Enumeration(cases: [.`a`] as [Self.Reason])),
                            Events.EventSchema.Property(name: "qualified", typeName: "Swift.Array<Swift.Optional<Reason>>", isOptional: false, hasInvalidConstraint: Events.ValidationKeyword.hasInvalidConstraint(of: \\Self.qualified), keywords: Events.ValidationKeyword.keywords(of: \\Self.qualified), enumeration: Events.EventSchema.Enumeration(cases: [.`a`] as [Self.Reason])),
                            Events.EventSchema.Property(name: "secret", typeName: "Events.Sensitive<Reason>", isOptional: false, hasInvalidConstraint: Events.ValidationKeyword.hasInvalidConstraint(of: \\Self.secret), keywords: Events.ValidationKeyword.keywords(of: \\Self.secret), enumeration: Events.EventSchema.Enumeration(cases: [.`a`] as [Self.Reason])),
                            Events.EventSchema.Property(name: "umbrella", typeName: "Traffluent.Sensitive<Reason>", isOptional: false, hasInvalidConstraint: Events.ValidationKeyword.hasInvalidConstraint(of: \\Self.umbrella), keywords: Events.ValidationKeyword.keywords(of: \\Self.umbrella), enumeration: Events.EventSchema.Enumeration(cases: [.`a`] as [Self.Reason])),
                        ])
                    }

                    private static func requireCodable(own: KeyPath<Self, some Swift.Codable>) {
                    }

                    private static func requireCodable(maybe: KeyPath<Self, some Swift.Codable>) {
                    }

                    private static func requireCodable(list: KeyPath<Self, some Swift.Codable>) {
                    }

                    private static func requireCodable(qualified: KeyPath<Self, some Swift.Codable>) {
                    }

                    private static func requireCodable(secret: KeyPath<Self, some Swift.Codable>) {
                    }

                    private static func requireCodable(umbrella: KeyPath<Self, some Swift.Codable>) {
                    }

                    private static var codableRequirements: Void {
                        requireCodable(own: \\.own)
                        requireCodable(maybe: \\.maybe)
                        requireCodable(list: \\.list)
                        requireCodable(qualified: \\.qualified)
                        requireCodable(secret: \\.secret)
                        requireCodable(umbrella: \\.umbrella)
                    }

                    private enum CodingKeys: Swift.String, Swift.CodingKey {
                        case own
                        case maybe
                        case list
                        case qualified
                        case secret
                        case umbrella
                    }

                    func encode(to encoder: any Swift.Encoder) throws {
                        var container = encoder.container(keyedBy: CodingKeys.self)
                        try container.encode(self.own, forKey: .own)
                        try container.encodeIfPresent(self.maybe, forKey: .maybe)
                        try container.encode(self.list, forKey: .list)
                        try container.encode(self.qualified, forKey: .qualified)
                        try container.encode(self.secret, forKey: .secret)
                        try container.encode(self.umbrella, forKey: .umbrella)
                    }

                    init(from decoder: any Swift.Decoder) throws {
                        let container = try decoder.container(keyedBy: CodingKeys.self)
                        self.own = try Self.decodeValue(from: container, forKey: .own)
                        self.maybe = try Self.decodeIfPresentValue(from: container, forKey: .maybe)
                        self.list = try Self.decodeValue(from: container, forKey: .list)
                        self.qualified = try Self.decodeValue(from: container, forKey: .qualified)
                        self.secret = try Self.decodeValue(from: container, forKey: .secret)
                        self.umbrella = try Self.decodeValue(from: container, forKey: .umbrella)
                    }

                    private static func decodeValue<Decoded: Swift.Decodable>(from container: Swift.KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> Decoded {
                        try container.decode(Decoded.self, forKey: key)
                    }

                    private static func decodeIfPresentValue<Decoded: Swift.Decodable>(from container: Swift.KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> Decoded? {
                        try container.decodeIfPresent(Decoded.self, forKey: key)
                    }
                }
                """,
            macroSpecs: ["Event": MacroSpec(type: EventMacro.self, conformances: ["Event", "Encodable", "Decodable", "__DiscoverableEvent"])],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test("A property of a type declared elsewhere, of an enum inside the event without a raw value the plan maps, or with a case under #if, reads its enumeration at run time")
    func enumerationAtRunTime() {
        assertMacroExpansion(
            """
            @Event
            struct Opened {
                enum Kind: Codable {
                    case cold
                }
                enum Source: Double, Codable {
                    case push = 1
                }
                enum Screen: Swift.Int, Codable {
                    case home
                    #if os(iOS)
                    case widget
                    #endif
                }
                enum Unused: String {
                    case a
                }
                var plan: Plan
                var kind: Kind
                var source: Source
                var screen: Self.Screen
            }
            """,
            expandedSource: """
                struct Opened {
                    enum Kind: Codable {
                        case cold
                    }
                    enum Source: Double, Codable {
                        case push = 1
                    }
                    enum Screen: Swift.Int, Codable {
                        case home
                        #if os(iOS)
                        case widget
                        #endif
                    }
                    enum Unused: String {
                        case a
                    }
                    var plan: Plan
                    var kind: Kind
                    var source: Source
                    var screen: Self.Screen
                }

                private enum __macro_local_15linkerSetRecordfMu_ {
                    #__eventRecord(kind: 0x65766E74, storing: Opened.self as any (Events.__DiscoverableEvent).Type)
                }

                nonisolated extension Opened: Events.Event, Swift.Encodable, Swift.Decodable, Events.__DiscoverableEvent {
                    static var schema: Events.EventSchema {
                        Events.EventSchema(name: Self.name, version: Self.schemaVersion, consentCategory: Self.consentCategory, properties: [
                            Events.EventSchema.Property(name: "plan", typeName: "Plan", isOptional: false, hasInvalidConstraint: Events.ValidationKeyword.hasInvalidConstraint(of: \\Self.plan), keywords: Events.ValidationKeyword.keywords(of: \\Self.plan), enumeration: Events.EventSchema.Enumeration(of: \\Self.plan)),
                            Events.EventSchema.Property(name: "kind", typeName: "Kind", isOptional: false, hasInvalidConstraint: Events.ValidationKeyword.hasInvalidConstraint(of: \\Self.kind), keywords: Events.ValidationKeyword.keywords(of: \\Self.kind), enumeration: Events.EventSchema.Enumeration(of: \\Self.kind)),
                            Events.EventSchema.Property(name: "source", typeName: "Source", isOptional: false, hasInvalidConstraint: Events.ValidationKeyword.hasInvalidConstraint(of: \\Self.source), keywords: Events.ValidationKeyword.keywords(of: \\Self.source), enumeration: Events.EventSchema.Enumeration(of: \\Self.source)),
                            Events.EventSchema.Property(name: "screen", typeName: "Self.Screen", isOptional: false, hasInvalidConstraint: Events.ValidationKeyword.hasInvalidConstraint(of: \\Self.screen), keywords: Events.ValidationKeyword.keywords(of: \\Self.screen), enumeration: Events.EventSchema.Enumeration(of: \\Self.screen)),
                        ])
                    }

                    private static func requireCodable(plan: KeyPath<Self, some Swift.Codable>) {
                    }

                    private static func requireCodable(kind: KeyPath<Self, some Swift.Codable>) {
                    }

                    private static func requireCodable(source: KeyPath<Self, some Swift.Codable>) {
                    }

                    private static func requireCodable(screen: KeyPath<Self, some Swift.Codable>) {
                    }

                    private static var codableRequirements: Void {
                        requireCodable(plan: \\.plan)
                        requireCodable(kind: \\.kind)
                        requireCodable(source: \\.source)
                        requireCodable(screen: \\.screen)
                    }

                    private enum CodingKeys: Swift.String, Swift.CodingKey {
                        case plan
                        case kind
                        case source
                        case screen
                    }

                    func encode(to encoder: any Swift.Encoder) throws {
                        var container = encoder.container(keyedBy: CodingKeys.self)
                        try container.encode(self.plan, forKey: .plan)
                        try container.encode(self.kind, forKey: .kind)
                        try container.encode(self.source, forKey: .source)
                        try container.encode(self.screen, forKey: .screen)
                    }

                    init(from decoder: any Swift.Decoder) throws {
                        let container = try decoder.container(keyedBy: CodingKeys.self)
                        self.plan = try Self.decodeValue(from: container, forKey: .plan)
                        self.kind = try Self.decodeValue(from: container, forKey: .kind)
                        self.source = try Self.decodeValue(from: container, forKey: .source)
                        self.screen = try Self.decodeValue(from: container, forKey: .screen)
                    }

                    private static func decodeValue<Decoded: Swift.Decodable>(from container: Swift.KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> Decoded {
                        try container.decode(Decoded.self, forKey: key)
                    }
                }
                """,
            macroSpecs: ["Event": MacroSpec(type: EventMacro.self, conformances: ["Event", "Encodable", "Decodable", "__DiscoverableEvent"])],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test("A raw-value enum inside the event that a property holds and whose inheritance clause lists no Codable is an error at that clause, once however many properties hold it", arguments: [
        "String", "Int, CaseIterable", "Swift.UInt8, Hashable, Sendable", "String, Encodable", "String, Swift.Hashable",
    ])
    func enumNotCodable(inheritance: String) {
        assertMacroExpansion(
            """
            @Event
            struct CheckoutFailed {
                enum Reason: \(inheritance) {
                    case declined
                }
                var reason: Reason
                var previous: Reason?
            }
            """,
            expandedSource: """
                struct CheckoutFailed {
                    enum Reason: \(inheritance) {
                        case declined
                    }
                    var reason: Reason
                    var previous: Reason?
                }
                """,
            diagnostics: [
                DiagnosticSpec(message: "@Event writes enum Reason as its raw value through Codable; add Codable to its inheritance clause", line: 3, column: 16),
            ],
            macroSpecs: ["Event": MacroSpec(type: EventMacro.self, conformances: ["Event", "Encodable", "Decodable", "__DiscoverableEvent"])],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test("An inheritance clause listing Codable, Encodable and Decodable, or a protocol the macro doesn't know, which may refine Codable, is no error", arguments: [
        "Codable", "Swift.Codable", "Encodable, Decodable", "Swift.Encodable, Swift.Decodable", "AnalyticsValue",
    ])
    func enumCodableOrUnknown(conformance: String) {
        assertMacroExpansion(
            """
            @Event
            struct CheckoutFailed {
                enum Reason: String, \(conformance) {
                    case declined
                }
                var reason: Reason
            }
            """,
            expandedSource: """
                struct CheckoutFailed {
                    enum Reason: String, \(conformance) {
                        case declined
                    }
                    var reason: Reason
                }

                private enum __macro_local_15linkerSetRecordfMu_ {
                    #__eventRecord(kind: 0x65766E74, storing: CheckoutFailed.self as any (Events.__DiscoverableEvent).Type)
                }

                nonisolated extension CheckoutFailed: Events.Event, Swift.Encodable, Swift.Decodable, Events.__DiscoverableEvent {
                    static var schema: Events.EventSchema {
                        Events.EventSchema(name: Self.name, version: Self.schemaVersion, consentCategory: Self.consentCategory, properties: [
                            Events.EventSchema.Property(name: "reason", typeName: "Reason", isOptional: false, hasInvalidConstraint: Events.ValidationKeyword.hasInvalidConstraint(of: \\Self.reason), keywords: Events.ValidationKeyword.keywords(of: \\Self.reason), enumeration: Events.EventSchema.Enumeration(cases: [.`declined`] as [Self.Reason])),
                        ])
                    }

                    private static func requireCodable(reason: KeyPath<Self, some Swift.Codable>) {
                    }

                    private static var codableRequirements: Void {
                        requireCodable(reason: \\.reason)
                    }

                    private enum CodingKeys: Swift.String, Swift.CodingKey {
                        case reason
                    }

                    func encode(to encoder: any Swift.Encoder) throws {
                        var container = encoder.container(keyedBy: CodingKeys.self)
                        try container.encode(self.reason, forKey: .reason)
                    }

                    init(from decoder: any Swift.Decoder) throws {
                        let container = try decoder.container(keyedBy: CodingKeys.self)
                        self.reason = try Self.decodeValue(from: container, forKey: .reason)
                    }

                    private static func decodeValue<Decoded: Swift.Decodable>(from container: Swift.KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> Decoded {
                        try container.decode(Decoded.self, forKey: key)
                    }
                }
                """,
            macroSpecs: ["Event": MacroSpec(type: EventMacro.self, conformances: ["Event", "Encodable", "Decodable", "__DiscoverableEvent"])],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test("An enum inside the event that gains Codable only in an extension is still an error: the macro sees the struct alone, so the clause must list it")
    func enumCodableInExtension() {
        assertMacroExpansion(
            """
            @Event
            struct CheckoutFailed {
                enum Reason: String {
                    case declined
                }
                var reason: Reason
            }

            extension CheckoutFailed.Reason: Codable {}
            """,
            expandedSource: """
                struct CheckoutFailed {
                    enum Reason: String {
                        case declined
                    }
                    var reason: Reason
                }

                extension CheckoutFailed.Reason: Codable {}
                """,
            diagnostics: [
                DiagnosticSpec(message: "@Event writes enum Reason as its raw value through Codable; add Codable to its inheritance clause", line: 3, column: 16),
            ],
            macroSpecs: ["Event": MacroSpec(type: EventMacro.self, conformances: ["Event", "Encodable", "Decodable", "__DiscoverableEvent"])],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test("Each case is named in backticks, so one named after a keyword, as written in backticks, names the case")
    func keywordCases() {
        assertMacroExpansion(
            """
            @Event
            struct Shape {
                enum Kind: String, Codable {
                    case `Type`
                    case `self`
                    case plain
                }
                var kind: Kind
            }
            """,
            expandedSource: """
                struct Shape {
                    enum Kind: String, Codable {
                        case `Type`
                        case `self`
                        case plain
                    }
                    var kind: Kind
                }

                private enum __macro_local_15linkerSetRecordfMu_ {
                    #__eventRecord(kind: 0x65766E74, storing: Shape.self as any (Events.__DiscoverableEvent).Type)
                }

                nonisolated extension Shape: Events.Event, Swift.Encodable, Swift.Decodable, Events.__DiscoverableEvent {
                    static var schema: Events.EventSchema {
                        Events.EventSchema(name: Self.name, version: Self.schemaVersion, consentCategory: Self.consentCategory, properties: [
                            Events.EventSchema.Property(name: "kind", typeName: "Kind", isOptional: false, hasInvalidConstraint: Events.ValidationKeyword.hasInvalidConstraint(of: \\Self.kind), keywords: Events.ValidationKeyword.keywords(of: \\Self.kind), enumeration: Events.EventSchema.Enumeration(cases: [.`Type`, .`self`, .`plain`] as [Self.Kind])),
                        ])
                    }

                    private static func requireCodable(kind: KeyPath<Self, some Swift.Codable>) {
                    }

                    private static var codableRequirements: Void {
                        requireCodable(kind: \\.kind)
                    }

                    private enum CodingKeys: Swift.String, Swift.CodingKey {
                        case kind
                    }

                    func encode(to encoder: any Swift.Encoder) throws {
                        var container = encoder.container(keyedBy: CodingKeys.self)
                        try container.encode(self.kind, forKey: .kind)
                    }

                    init(from decoder: any Swift.Decoder) throws {
                        let container = try decoder.container(keyedBy: CodingKeys.self)
                        self.kind = try Self.decodeValue(from: container, forKey: .kind)
                    }

                    private static func decodeValue<Decoded: Swift.Decodable>(from container: Swift.KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> Decoded {
                        try container.decode(Decoded.self, forKey: key)
                    }
                }
                """,
            macroSpecs: ["Event": MacroSpec(type: EventMacro.self, conformances: ["Event", "Encodable", "Decodable", "__DiscoverableEvent"])],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }
}
