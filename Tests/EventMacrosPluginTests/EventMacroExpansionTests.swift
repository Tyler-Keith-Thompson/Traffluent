// The @Event macro's expansions, pinned. Each test is self-contained.
//
// A discovery record is pinned as the one #__eventRecord call the expansion writes, which
// assertMacroExpansion leaves unexpanded as it isn't in the table: the per-format declarations
// behind it are LinkerSets' (LinkerSetRecordMacro), so these tests pin only Traffluent's part, the
// same on every swift-syntax the plugin accepts. The function after it, whose symbol holds the
// event's name so the linker refuses a second event of that name, is pinned as written.

import EventMacrosPlugin
import SwiftSyntax
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacros
import SwiftSyntaxMacrosGenericTestSupport
import Testing

@Suite("@Event expansions")
struct EventMacroExpansionTests {
    @Test("A struct gets Event, Encodable and Decodable, a schema, a requirement per property, its coding keys and its coding, each property under its name")
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

                private enum __macro_local_15linkerSetRecordfMu_ {
                    #__eventRecord(kind: 0x65766E74, storing: SignedUp.self as any (Events.__DiscoverableEvent).Type)
                }

                @_silgen_name("$linkerset_kind_65766E74_key_SignedUp") @used nonisolated func __macro_local_18linkerSetUniqueKeyfMu_() {
                }

                nonisolated extension SignedUp: Events.Event, Swift.Encodable, Swift.Decodable, Events.__DiscoverableEvent {
                    static var name: String {
                        String(describing: Self.self)
                    }

                    static var schema: Events.EventSchema {
                        Events.EventSchema(name: Self.name, version: Self.schemaVersion, consentCategory: Self.consentCategory, properties: [
                            Events.EventSchema.Property(name: "plan", typeName: "String", isOptional: false, hasInvalidConstraint: Events.ValidationKeyword.hasInvalidConstraint(of: \\Self.plan), keywords: Events.ValidationKeyword.keywords(of: \\Self.plan)),
                            Events.EventSchema.Property(name: "seats", typeName: "Int", isOptional: true, hasInvalidConstraint: Events.ValidationKeyword.hasInvalidConstraint(of: \\Self.seats), keywords: Events.ValidationKeyword.keywords(of: \\Self.seats)),
                        ])
                    }

                    private static func requireCodable(plan: KeyPath<Self, some Swift.Codable>) {
                    }

                    private static func requireCodable(seats: KeyPath<Self, some Swift.Codable>) {
                    }

                    private static var codableRequirements: Void {
                        requireCodable(plan: \\.plan)
                        requireCodable(seats: \\.seats)
                    }

                    private enum CodingKeys: Swift.String, Swift.CodingKey {
                        case plan
                        case seats
                    }

                    func encode(to encoder: any Swift.Encoder) throws {
                        var container = encoder.container(keyedBy: CodingKeys.self)
                        try container.encode(self.plan, forKey: .plan)
                        try container.encodeIfPresent(self.seats, forKey: .seats)
                    }

                    init(from decoder: any Swift.Decoder) throws {
                        let container = try decoder.container(keyedBy: CodingKeys.self)
                        self.plan = try container.decode(String.self, forKey: .plan)
                        self.seats = try container.decodeIfPresent(Int.self, forKey: .seats)
                    }
                }
                """,
            macroSpecs: ["Event": MacroSpec(type: EventMacro.self, conformances: ["Event", "Encodable", "Decodable", "__DiscoverableEvent"])],
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

                private enum __macro_local_15linkerSetRecordfMu_ {
                    #__eventRecord(kind: 0x65766E74, storing: CartViewed.self as any (Events.__DiscoverableEvent).Type)
                }

                @_silgen_name("$linkerset_kind_65766E74_key_CartViewed") @used nonisolated func __macro_local_18linkerSetUniqueKeyfMu_() {
                }

                nonisolated extension CartViewed: Events.Event, Swift.Encodable, Swift.Decodable, Events.__DiscoverableEvent {
                    public static var name: String {
                        String(describing: Self.self)
                    }

                    public static var schema: Events.EventSchema {
                        Events.EventSchema(name: Self.name, version: Self.schemaVersion, consentCategory: Self.consentCategory, properties: [
                            Events.EventSchema.Property(name: "currency", typeName: "String", isOptional: false, hasDefaultValue: true, hasInvalidConstraint: Events.ValidationKeyword.hasInvalidConstraint(of: \\Self.currency), keywords: Events.ValidationKeyword.keywords(of: \\Self.currency)),
                            Events.EventSchema.Property(name: "coupon", typeName: "String", isOptional: true, hasDefaultValue: true, hasInvalidConstraint: Events.ValidationKeyword.hasInvalidConstraint(of: \\Self.coupon), keywords: Events.ValidationKeyword.keywords(of: \\Self.coupon)),
                        ])
                    }

                    private static func requireCodable(currency: KeyPath<Self, some Swift.Codable>) {
                    }

                    private static func requireCodable(coupon: KeyPath<Self, some Swift.Codable>) {
                    }

                    private static var codableRequirements: Void {
                        requireCodable(currency: \\.currency)
                        requireCodable(coupon: \\.coupon)
                    }

                    private enum CodingKeys: Swift.String, Swift.CodingKey {
                        case currency
                        case coupon
                    }

                    public func encode(to encoder: any Swift.Encoder) throws {
                        var container = encoder.container(keyedBy: CodingKeys.self)
                        try container.encode(self.currency, forKey: .currency)
                        try container.encode(self.coupon, forKey: .coupon)
                    }

                    public init(from decoder: any Swift.Decoder) throws {
                        let container = try decoder.container(keyedBy: CodingKeys.self)
                        if container.contains(.currency) {
                            self.currency = try container.decode(String.self, forKey: .currency)
                        }
                        if container.contains(.coupon) {
                            self.coupon = try container.decodeIfPresent(String.self, forKey: .coupon)
                        }
                    }
                }
                """,
            macroSpecs: ["Event": MacroSpec(type: EventMacro.self, conformances: ["Event", "Encodable", "Decodable", "__DiscoverableEvent"])],
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

                private enum __macro_local_15linkerSetRecordfMu_ {
                    #__eventRecord(kind: 0x65766E74, storing: AdClicked.self as any (Events.__DiscoverableEvent).Type)
                }

                @_silgen_name("$linkerset_kind_65766E74_key_ad_5Fclicked") @used nonisolated func __macro_local_18linkerSetUniqueKeyfMu_() {
                }

                nonisolated extension AdClicked: Events.Event, Swift.Encodable, Swift.Decodable, Events.__DiscoverableEvent {
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
                            Events.EventSchema.Property(name: "campaign", typeName: "String", isOptional: false, hasInvalidConstraint: Events.ValidationKeyword.hasInvalidConstraint(of: \Self.campaign), keywords: Events.ValidationKeyword.keywords(of: \Self.campaign)),
                        ])
                    }

                    private static func requireCodable(campaign: KeyPath<Self, some Swift.Codable>) {
                    }

                    private static var codableRequirements: Void {
                        requireCodable(campaign: \.campaign)
                    }

                    private enum CodingKeys: Swift.String, Swift.CodingKey {
                        case campaign
                    }

                    func encode(to encoder: any Swift.Encoder) throws {
                        var container = encoder.container(keyedBy: CodingKeys.self)
                        try container.encode(self.campaign, forKey: .campaign)
                    }

                    init(from decoder: any Swift.Decoder) throws {
                        let container = try decoder.container(keyedBy: CodingKeys.self)
                        self.campaign = try container.decode(String.self, forKey: .campaign)
                    }
                }
                """#,
            macroSpecs: ["Event": MacroSpec(type: EventMacro.self, conformances: ["Event", "Encodable", "Decodable", "__DiscoverableEvent"])],
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

                private enum __macro_local_15linkerSetRecordfMu_ {
                    #__eventRecord(kind: 0x65766E74, storing: Opened.self as any (Events.__DiscoverableEvent).Type)
                }

                @_silgen_name("$linkerset_kind_65766E74_key_Opened") @used nonisolated func __macro_local_18linkerSetUniqueKeyfMu_() {
                }

                nonisolated extension Opened: Events.Event, Swift.Encodable, Swift.Decodable, Events.__DiscoverableEvent {
                    static var name: String {
                        String(describing: Self.self)
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

    // On a generic struct, which gets no discovery record, so the test runs on every swift-syntax
    // the plugin accepts.
    @Test("The extension is nonisolated, so a struct marked @MainActor conforms off the main actor, and so would one isolated by a module's default if a compiler applied it to the expansion")
    func nonisolatedExtension() {
        assertMacroExpansion(
            """
            @MainActor
            @Event(name: "opened")
            struct Opened<Value> {
                var screen: String
            }
            """,
            expandedSource: """
                @MainActor
                struct Opened<Value> {
                    var screen: String
                }

                nonisolated extension Opened: Events.Event, Swift.Encodable, Swift.Decodable {
                    static var name: String {
                        "opened"
                    }

                    static var schema: Events.EventSchema {
                        Events.EventSchema(name: Self.name, version: Self.schemaVersion, consentCategory: Self.consentCategory, properties: [
                            Events.EventSchema.Property(name: "screen", typeName: "String", isOptional: false, hasInvalidConstraint: Events.ValidationKeyword.hasInvalidConstraint(of: \\Self.screen), keywords: Events.ValidationKeyword.keywords(of: \\Self.screen)),
                        ])
                    }

                    private static func requireCodable(screen: KeyPath<Self, some Swift.Codable>) {
                    }

                    private static var codableRequirements: Void {
                        requireCodable(screen: \\.screen)
                    }

                    private enum CodingKeys: Swift.String, Swift.CodingKey {
                        case screen
                    }

                    func encode(to encoder: any Swift.Encoder) throws {
                        var container = encoder.container(keyedBy: CodingKeys.self)
                        try container.encode(self.screen, forKey: .screen)
                    }

                    init(from decoder: any Swift.Decoder) throws {
                        let container = try decoder.container(keyedBy: CodingKeys.self)
                        self.screen = try container.decode(String.self, forKey: .screen)
                    }
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@Event can't give a generic struct the record DiscoveredEvent.all finds events by; list it explicitly, in SegmentStore(events:) and TrackingPlan(schemas:)",
                    line: 3, column: 14, severity: .note),
            ],
            macroSpecs: ["Event": MacroSpec(type: EventMacro.self, conformances: ["Event", "Encodable", "Decodable", "__DiscoverableEvent"])],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test(
        "A version literal is read in its radix, without its underscores",
        // On a generic struct, which gets no discovery record, so the test runs on every
        // swift-syntax the plugin accepts: 600 reads the literal through the plugin's own
        // representedLiteralValue, which 601 replaces.
        arguments: [("0b11", 3), ("0o12", 10), ("0x1F", 31), ("1_0", 10), ("0x7FFF_FFFF", 2_147_483_647)]
    )
    func versionLiteralRadix(literal: String, expectedVersion: Int) {
        assertMacroExpansion(
            """
            @Event(version: \(literal))
            struct Opened<Value> {
            }
            """,
            expandedSource: """
                struct Opened<Value> {
                }

                nonisolated extension Opened: Events.Event, Swift.Encodable, Swift.Decodable {
                    static var name: String {
                        String(describing: Self.self)
                    }

                    static var schemaVersion: Int {
                        \(expectedVersion)
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
            diagnostics: [
                DiagnosticSpec(
                    message: "@Event can't give a generic struct the record DiscoveredEvent.all finds events by; list it explicitly, in SegmentStore(events:) and TrackingPlan(schemas:)",
                    line: 2, column: 14, severity: .note),
            ],
            macroSpecs: ["Event": MacroSpec(type: EventMacro.self, conformances: ["Event", "Encodable", "Decodable", "__DiscoverableEvent"])],
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

                private enum __macro_local_15linkerSetRecordfMu_ {
                    #__eventRecord(kind: 0x65766E74, storing: Crashed.self as any (Events.__DiscoverableEvent).Type)
                }

                @_silgen_name("$linkerset_kind_65766E74_key_crash") @used nonisolated func __macro_local_18linkerSetUniqueKeyfMu_() {
                }

                nonisolated extension Crashed: Events.Event, Swift.Encodable, Swift.Decodable, Events.__DiscoverableEvent {
                    static var name: String {
                        #"crash"#
                    }

                    static var consentCategory: Events.ConsentCategory {
                        ConsentCategory("crash-reports")
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
                """##,
            macroSpecs: ["Event": MacroSpec(type: EventMacro.self, conformances: ["Event", "Encodable", "Decodable", "__DiscoverableEvent"])],
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

                private enum __macro_local_15linkerSetRecordfMu_ {
                    #__eventRecord(kind: 0x65766E74, storing: A.self as any (Events.__DiscoverableEvent).Type)
                }

                @_silgen_name("$linkerset_kind_65766E74_key_a") @used nonisolated func __macro_local_18linkerSetUniqueKeyfMu_() {
                }
                package struct B {
                }

                private enum __macro_local_15linkerSetRecordfMu0_ {
                    #__eventRecord(kind: 0x65766E74, storing: B.self as any (Events.__DiscoverableEvent).Type)
                }

                @_silgen_name("$linkerset_kind_65766E74_key_B") @used nonisolated func __macro_local_18linkerSetUniqueKeyfMu0_() {
                }

                nonisolated extension A: Events.Event, Swift.Encodable, Swift.Decodable, Events.__DiscoverableEvent {
                    public static var name: String {
                        "a"
                    }

                    public static var schema: Events.EventSchema {
                        Events.EventSchema(name: Self.name, version: Self.schemaVersion, consentCategory: Self.consentCategory, properties: [])
                    }

                    private enum CodingKeys: Swift.CodingKey {
                    }

                    public func encode(to encoder: any Swift.Encoder) throws {
                        _ = encoder.container(keyedBy: CodingKeys.self)
                    }

                    public init(from decoder: any Swift.Decoder) throws {
                        _ = try decoder.container(keyedBy: CodingKeys.self)
                    }
                }

                nonisolated extension B: Events.Event, Swift.Encodable, Swift.Decodable, Events.__DiscoverableEvent {
                    package static var name: String {
                        String(describing: Self.self)
                    }

                    package static var consentCategory: Events.ConsentCategory {
                        .functional
                    }

                    package static var schema: Events.EventSchema {
                        Events.EventSchema(name: Self.name, version: Self.schemaVersion, consentCategory: Self.consentCategory, properties: [])
                    }

                    private enum CodingKeys: Swift.CodingKey {
                    }

                    package func encode(to encoder: any Swift.Encoder) throws {
                        _ = encoder.container(keyedBy: CodingKeys.self)
                    }

                    package init(from decoder: any Swift.Decoder) throws {
                        _ = try decoder.container(keyedBy: CodingKeys.self)
                    }
                }
                """,
            macroSpecs: ["Event": MacroSpec(type: EventMacro.self, conformances: ["Event", "Encodable", "Decodable", "__DiscoverableEvent"])],
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

                private enum __macro_local_15linkerSetRecordfMu_ {
                    #__eventRecord(kind: 0x65766E74, storing: Shapes.self as any (Events.__DiscoverableEvent).Type)
                }

                @_silgen_name("$linkerset_kind_65766E74_key_Shapes") @used nonisolated func __macro_local_18linkerSetUniqueKeyfMu_() {
                }

                nonisolated extension Shapes: Events.Event, Swift.Encodable, Swift.Decodable, Events.__DiscoverableEvent {
                    static var name: String {
                        String(describing: Self.self)
                    }

                    static var schema: Events.EventSchema {
                        Events.EventSchema(name: Self.name, version: Self.schemaVersion, consentCategory: Self.consentCategory, properties: [
                            Events.EventSchema.Property(name: "assigned", typeName: "Bool", isOptional: false, hasInvalidConstraint: Events.ValidationKeyword.hasInvalidConstraint(of: \\Self.assigned), keywords: Events.ValidationKeyword.keywords(of: \\Self.assigned)),
                            Events.EventSchema.Property(name: "first", typeName: "UInt16", isOptional: false, hasInvalidConstraint: Events.ValidationKeyword.hasInvalidConstraint(of: \\Self.first), keywords: Events.ValidationKeyword.keywords(of: \\Self.first)),
                            Events.EventSchema.Property(name: "second", typeName: "UInt16", isOptional: false, hasInvalidConstraint: Events.ValidationKeyword.hasInvalidConstraint(of: \\Self.second), keywords: Events.ValidationKeyword.keywords(of: \\Self.second)),
                            Events.EventSchema.Property(name: "observed", typeName: "Int32", isOptional: false, hasDefaultValue: true, hasInvalidConstraint: Events.ValidationKeyword.hasInvalidConstraint(of: \\Self.observed), keywords: Events.ValidationKeyword.keywords(of: \\Self.observed)),
                        ])
                    }

                    private static func requireCodable(assigned: KeyPath<Self, some Swift.Codable>) {
                    }

                    private static func requireCodable(first: KeyPath<Self, some Swift.Codable>) {
                    }

                    private static func requireCodable(second: KeyPath<Self, some Swift.Codable>) {
                    }

                    private static func requireCodable(observed: KeyPath<Self, some Swift.Codable>) {
                    }

                    private static var codableRequirements: Void {
                        requireCodable(assigned: \\.assigned)
                        requireCodable(first: \\.first)
                        requireCodable(second: \\.second)
                        requireCodable(observed: \\.observed)
                    }

                    private enum CodingKeys: Swift.String, Swift.CodingKey {
                        case assigned
                        case first
                        case second
                        case observed
                    }

                    func encode(to encoder: any Swift.Encoder) throws {
                        var container = encoder.container(keyedBy: CodingKeys.self)
                        try container.encode(self.assigned, forKey: .assigned)
                        try container.encode(self.first, forKey: .first)
                        try container.encode(self.second, forKey: .second)
                        try container.encode(self.observed, forKey: .observed)
                    }

                    init(from decoder: any Swift.Decoder) throws {
                        let container = try decoder.container(keyedBy: CodingKeys.self)
                        self.assigned = try container.decode(Bool.self, forKey: .assigned)
                        self.first = try container.decode(UInt16.self, forKey: .first)
                        self.second = try container.decode(UInt16.self, forKey: .second)
                        if container.contains(.observed) {
                            self.observed = try container.decode(Int32.self, forKey: .observed)
                        }
                    }
                }
                """,
            macroSpecs: ["Event": MacroSpec(type: EventMacro.self, conformances: ["Event", "Encodable", "Decodable", "__DiscoverableEvent"])],
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

                private enum __macro_local_15linkerSetRecordfMu_ {
                    #__eventRecord(kind: 0x65766E74, storing: Spellings.self as any (Events.__DiscoverableEvent).Type)
                }

                @_silgen_name("$linkerset_kind_65766E74_key_Spellings") @used nonisolated func __macro_local_18linkerSetUniqueKeyfMu_() {
                }

                nonisolated extension Spellings: Events.Event, Swift.Encodable, Swift.Decodable, Events.__DiscoverableEvent {
                    static var name: String {
                        String(describing: Self.self)
                    }

                    static var schema: Events.EventSchema {
                        Events.EventSchema(name: Self.name, version: Self.schemaVersion, consentCategory: Self.consentCategory, properties: [
                            Events.EventSchema.Property(name: "a", typeName: "Int", isOptional: true, hasInvalidConstraint: Events.ValidationKeyword.hasInvalidConstraint(of: \\Self.a), keywords: Events.ValidationKeyword.keywords(of: \\Self.a)),
                            Events.EventSchema.Property(name: "b", typeName: "Int", isOptional: true, hasInvalidConstraint: Events.ValidationKeyword.hasInvalidConstraint(of: \\Self.b), keywords: Events.ValidationKeyword.keywords(of: \\Self.b)),
                            Events.EventSchema.Property(name: "c", typeName: "Int", isOptional: true, hasInvalidConstraint: Events.ValidationKeyword.hasInvalidConstraint(of: \\Self.c), keywords: Events.ValidationKeyword.keywords(of: \\Self.c)),
                            Events.EventSchema.Property(name: "d", typeName: "Int", isOptional: true, hasInvalidConstraint: Events.ValidationKeyword.hasInvalidConstraint(of: \\Self.d), keywords: Events.ValidationKeyword.keywords(of: \\Self.d)),
                            Events.EventSchema.Property(name: "e", typeName: "[Int?]", isOptional: false, hasInvalidConstraint: Events.ValidationKeyword.hasInvalidConstraint(of: \\Self.e), keywords: Events.ValidationKeyword.keywords(of: \\Self.e), enumeration: Events.EventSchema.Enumeration(of: \\Self.e)),
                            Events.EventSchema.Property(name: "f", typeName: "Mine.Optional<Int>", isOptional: false, hasInvalidConstraint: Events.ValidationKeyword.hasInvalidConstraint(of: \\Self.f), keywords: Events.ValidationKeyword.keywords(of: \\Self.f), enumeration: Events.EventSchema.Enumeration(of: \\Self.f)),
                            Events.EventSchema.Property(name: "g", typeName: "Int?", isOptional: true, hasInvalidConstraint: Events.ValidationKeyword.hasInvalidConstraint(of: \\Self.g), keywords: Events.ValidationKeyword.keywords(of: \\Self.g), enumeration: Events.EventSchema.Enumeration(of: \\Self.g)),
                            Events.EventSchema.Property(name: "h", typeName: "Array<Int>", isOptional: false, hasInvalidConstraint: Events.ValidationKeyword.hasInvalidConstraint(of: \\Self.h), keywords: Events.ValidationKeyword.keywords(of: \\Self.h), enumeration: Events.EventSchema.Enumeration(of: \\Self.h)),
                        ])
                    }

                    private static func requireCodable(a: KeyPath<Self, some Swift.Codable>) {
                    }

                    private static func requireCodable(b: KeyPath<Self, some Swift.Codable>) {
                    }

                    private static func requireCodable(c: KeyPath<Self, some Swift.Codable>) {
                    }

                    private static func requireCodable(d: KeyPath<Self, some Swift.Codable>) {
                    }

                    private static func requireCodable(e: KeyPath<Self, some Swift.Codable>) {
                    }

                    private static func requireCodable(f: KeyPath<Self, some Swift.Codable>) {
                    }

                    private static func requireCodable(g: KeyPath<Self, some Swift.Codable>) {
                    }

                    private static func requireCodable(h: KeyPath<Self, some Swift.Codable>) {
                    }

                    private static var codableRequirements: Void {
                        requireCodable(a: \\.a)
                        requireCodable(b: \\.b)
                        requireCodable(c: \\.c)
                        requireCodable(d: \\.d)
                        requireCodable(e: \\.e)
                        requireCodable(f: \\.f)
                        requireCodable(g: \\.g)
                        requireCodable(h: \\.h)
                    }

                    private enum CodingKeys: Swift.String, Swift.CodingKey {
                        case a
                        case b
                        case c
                        case d
                        case e
                        case f
                        case g
                        case h
                    }

                    func encode(to encoder: any Swift.Encoder) throws {
                        var container = encoder.container(keyedBy: CodingKeys.self)
                        try container.encodeIfPresent(self.a, forKey: .a)
                        try container.encodeIfPresent(self.b, forKey: .b)
                        try container.encodeIfPresent(self.c, forKey: .c)
                        try container.encodeIfPresent(self.d, forKey: .d)
                        try container.encode(self.e, forKey: .e)
                        try container.encode(self.f, forKey: .f)
                        try container.encodeIfPresent(self.g, forKey: .g)
                        try container.encode(self.h, forKey: .h)
                    }

                    init(from decoder: any Swift.Decoder) throws {
                        let container = try decoder.container(keyedBy: CodingKeys.self)
                        self.a = try container.decodeIfPresent(Int.self, forKey: .a)
                        self.b = try container.decodeIfPresent(Int.self, forKey: .b)
                        self.c = try container.decodeIfPresent(Int.self, forKey: .c)
                        self.d = try container.decodeIfPresent(Int.self, forKey: .d)
                        self.e = try Self.decodeValue(from: container, forKey: .e)
                        self.f = try Self.decodeValue(from: container, forKey: .f)
                        self.g = try Self.decodeIfPresentValue(from: container, forKey: .g)
                        self.h = try Self.decodeValue(from: container, forKey: .h)
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

                private enum __macro_local_15linkerSetRecordfMu_ {
                    #__eventRecord(kind: 0x65766E74, storing: Keywords.self as any (Events.__DiscoverableEvent).Type)
                }

                @_silgen_name("$linkerset_kind_65766E74_key_Keywords") @used nonisolated func __macro_local_18linkerSetUniqueKeyfMu_() {
                }

                nonisolated extension Keywords: Events.Event, Swift.Encodable, Swift.Decodable, Events.__DiscoverableEvent {
                    static var name: String {
                        String(describing: Self.self)
                    }

                    static var schema: Events.EventSchema {
                        Events.EventSchema(name: Self.name, version: Self.schemaVersion, consentCategory: Self.consentCategory, properties: [
                            Events.EventSchema.Property(name: "default", typeName: "Int", isOptional: false, hasInvalidConstraint: Events.ValidationKeyword.hasInvalidConstraint(of: \\Self.`default`), keywords: Events.ValidationKeyword.keywords(of: \\Self.`default`)),
                            Events.EventSchema.Property(name: "var", typeName: "Int", isOptional: false, hasInvalidConstraint: Events.ValidationKeyword.hasInvalidConstraint(of: \\Self.`var`), keywords: Events.ValidationKeyword.keywords(of: \\Self.`var`)),
                        ])
                    }

                    private static func requireCodable(default: KeyPath<Self, some Swift.Codable>) {
                    }

                    private static func requireCodable(`var`: KeyPath<Self, some Swift.Codable>) {
                    }

                    private static var codableRequirements: Void {
                        requireCodable(default: \\.`default`)
                        requireCodable(`var`: \\.`var`)
                    }

                    private enum CodingKeys: Swift.String, Swift.CodingKey {
                        case `default`
                        case `var`
                    }

                    func encode(to encoder: any Swift.Encoder) throws {
                        var container = encoder.container(keyedBy: CodingKeys.self)
                        try container.encode(self.`default`, forKey: .`default`)
                        try container.encode(self.`var`, forKey: .`var`)
                    }

                    init(from decoder: any Swift.Decoder) throws {
                        let container = try decoder.container(keyedBy: CodingKeys.self)
                        self.`default` = try container.decode(Int.self, forKey: .`default`)
                        self.`var` = try container.decode(Int.self, forKey: .`var`)
                    }
                }
                """,
            macroSpecs: ["Event": MacroSpec(type: EventMacro.self, conformances: ["Event", "Encodable", "Decodable", "__DiscoverableEvent"])],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test("A Date property is written as the seconds since 2001 it stores, and read back from them, optional or not, by any spelling of Date")
    func dates() {
        assertMacroExpansion(
            """
            @Event
            struct Purchased {
                var at: Date
                var shipped: Foundation.Date?
                var refunded: Date? = nil
            }
            """,
            expandedSource: """
                struct Purchased {
                    var at: Date
                    var shipped: Foundation.Date?
                    var refunded: Date? = nil
                }

                private enum __macro_local_15linkerSetRecordfMu_ {
                    #__eventRecord(kind: 0x65766E74, storing: Purchased.self as any (Events.__DiscoverableEvent).Type)
                }

                @_silgen_name("$linkerset_kind_65766E74_key_Purchased") @used nonisolated func __macro_local_18linkerSetUniqueKeyfMu_() {
                }

                nonisolated extension Purchased: Events.Event, Swift.Encodable, Swift.Decodable, Events.__DiscoverableEvent {
                    static var name: String {
                        String(describing: Self.self)
                    }

                    static var schema: Events.EventSchema {
                        Events.EventSchema(name: Self.name, version: Self.schemaVersion, consentCategory: Self.consentCategory, properties: [
                            Events.EventSchema.Property(name: "at", typeName: "Date", isOptional: false, hasInvalidConstraint: Events.ValidationKeyword.hasInvalidConstraint(of: \\Self.at), keywords: Events.ValidationKeyword.keywords(of: \\Self.at)),
                            Events.EventSchema.Property(name: "shipped", typeName: "Foundation.Date", isOptional: true, hasInvalidConstraint: Events.ValidationKeyword.hasInvalidConstraint(of: \\Self.shipped), keywords: Events.ValidationKeyword.keywords(of: \\Self.shipped)),
                            Events.EventSchema.Property(name: "refunded", typeName: "Date", isOptional: true, hasDefaultValue: true, hasInvalidConstraint: Events.ValidationKeyword.hasInvalidConstraint(of: \\Self.refunded), keywords: Events.ValidationKeyword.keywords(of: \\Self.refunded)),
                        ])
                    }

                    private static func requireCodable(at: KeyPath<Self, some Swift.Codable>) {
                    }

                    private static func requireCodable(shipped: KeyPath<Self, some Swift.Codable>) {
                    }

                    private static func requireCodable(refunded: KeyPath<Self, some Swift.Codable>) {
                    }

                    private static var codableRequirements: Void {
                        requireCodable(at: \\.at)
                        requireCodable(shipped: \\.shipped)
                        requireCodable(refunded: \\.refunded)
                    }

                    private enum CodingKeys: Swift.String, Swift.CodingKey {
                        case at
                        case shipped
                        case refunded
                    }

                    func encode(to encoder: any Swift.Encoder) throws {
                        var container = encoder.container(keyedBy: CodingKeys.self)
                        try container.encode(self.at.timeIntervalSinceReferenceDate, forKey: .at)
                        try container.encodeIfPresent(self.shipped?.timeIntervalSinceReferenceDate, forKey: .shipped)
                        try container.encode(self.refunded?.timeIntervalSinceReferenceDate, forKey: .refunded)
                    }

                    init(from decoder: any Swift.Decoder) throws {
                        let container = try decoder.container(keyedBy: CodingKeys.self)
                        self.at = try Date(timeIntervalSinceReferenceDate: container.decode(Swift.Double.self, forKey: .at))
                        self.shipped = try container.decodeIfPresent(Swift.Double.self, forKey: .shipped).map(Foundation.Date.init(timeIntervalSinceReferenceDate:))
                        if container.contains(.refunded) {
                            self.refunded = try container.decodeIfPresent(Swift.Double.self, forKey: .refunded).map(Date.init(timeIntervalSinceReferenceDate:))
                        }
                    }
                }
                """,
            macroSpecs: ["Event": MacroSpec(type: EventMacro.self, conformances: ["Event", "Encodable", "Decodable", "__DiscoverableEvent"])],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test("An array of dates or of optional dates is written as the seconds since 2001 each stores, and read back from them, the array optional or not")
    func dateArrays() {
        assertMacroExpansion(
            """
            @Event
            struct Scheduled {
                var slots: [Date]
                var maybe: [Foundation.Date?]
                var later: [Date]?
            }
            """,
            expandedSource: """
                struct Scheduled {
                    var slots: [Date]
                    var maybe: [Foundation.Date?]
                    var later: [Date]?
                }

                private enum __macro_local_15linkerSetRecordfMu_ {
                    #__eventRecord(kind: 0x65766E74, storing: Scheduled.self as any (Events.__DiscoverableEvent).Type)
                }

                @_silgen_name("$linkerset_kind_65766E74_key_Scheduled") @used nonisolated func __macro_local_18linkerSetUniqueKeyfMu_() {
                }

                nonisolated extension Scheduled: Events.Event, Swift.Encodable, Swift.Decodable, Events.__DiscoverableEvent {
                    static var name: String {
                        String(describing: Self.self)
                    }

                    static var schema: Events.EventSchema {
                        Events.EventSchema(name: Self.name, version: Self.schemaVersion, consentCategory: Self.consentCategory, properties: [
                            Events.EventSchema.Property(name: "slots", typeName: "[Date]", isOptional: false, hasInvalidConstraint: Events.ValidationKeyword.hasInvalidConstraint(of: \\Self.slots), keywords: Events.ValidationKeyword.keywords(of: \\Self.slots)),
                            Events.EventSchema.Property(name: "maybe", typeName: "[Foundation.Date?]", isOptional: false, hasInvalidConstraint: Events.ValidationKeyword.hasInvalidConstraint(of: \\Self.maybe), keywords: Events.ValidationKeyword.keywords(of: \\Self.maybe)),
                            Events.EventSchema.Property(name: "later", typeName: "[Date]", isOptional: true, hasInvalidConstraint: Events.ValidationKeyword.hasInvalidConstraint(of: \\Self.later), keywords: Events.ValidationKeyword.keywords(of: \\Self.later)),
                        ])
                    }

                    private static func requireCodable(slots: KeyPath<Self, some Swift.Codable>) {
                    }

                    private static func requireCodable(maybe: KeyPath<Self, some Swift.Codable>) {
                    }

                    private static func requireCodable(later: KeyPath<Self, some Swift.Codable>) {
                    }

                    private static var codableRequirements: Void {
                        requireCodable(slots: \\.slots)
                        requireCodable(maybe: \\.maybe)
                        requireCodable(later: \\.later)
                    }

                    private enum CodingKeys: Swift.String, Swift.CodingKey {
                        case slots
                        case maybe
                        case later
                    }

                    func encode(to encoder: any Swift.Encoder) throws {
                        var container = encoder.container(keyedBy: CodingKeys.self)
                        try container.encode(self.slots.map(\\.timeIntervalSinceReferenceDate), forKey: .slots)
                        try container.encode(self.maybe.map {
                                $0?.timeIntervalSinceReferenceDate
                            }, forKey: .maybe)
                        try container.encodeIfPresent(self.later?.map(\\.timeIntervalSinceReferenceDate), forKey: .later)
                    }

                    init(from decoder: any Swift.Decoder) throws {
                        let container = try decoder.container(keyedBy: CodingKeys.self)
                        self.slots = try container.decode([Swift.Double].self, forKey: .slots).map(Date.init(timeIntervalSinceReferenceDate:))
                        self.maybe = try container.decode([Swift.Double?].self, forKey: .maybe).map {
                            $0.map(Foundation.Date.init(timeIntervalSinceReferenceDate:))
                        }
                        self.later = try container.decodeIfPresent([Swift.Double].self, forKey: .later).map {
                            $0.map(Date.init(timeIntervalSinceReferenceDate:))
                        }
                    }
                }
                """,
            macroSpecs: ["Event": MacroSpec(type: EventMacro.self, conformances: ["Event", "Encodable", "Decodable", "__DiscoverableEvent"])],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test("A standard scalar, as written or qualified by Swift, is read by the container's method for its type; any other type through a generic function")
    func standardScalars() {
        assertMacroExpansion(
            """
            @Event
            struct Counted {
                var label: Swift.String
                var count: Int
                var tags: [String]
            }
            """,
            expandedSource: """
                struct Counted {
                    var label: Swift.String
                    var count: Int
                    var tags: [String]
                }

                private enum __macro_local_15linkerSetRecordfMu_ {
                    #__eventRecord(kind: 0x65766E74, storing: Counted.self as any (Events.__DiscoverableEvent).Type)
                }

                @_silgen_name("$linkerset_kind_65766E74_key_Counted") @used nonisolated func __macro_local_18linkerSetUniqueKeyfMu_() {
                }

                nonisolated extension Counted: Events.Event, Swift.Encodable, Swift.Decodable, Events.__DiscoverableEvent {
                    static var name: String {
                        String(describing: Self.self)
                    }

                    static var schema: Events.EventSchema {
                        Events.EventSchema(name: Self.name, version: Self.schemaVersion, consentCategory: Self.consentCategory, properties: [
                            Events.EventSchema.Property(name: "label", typeName: "Swift.String", isOptional: false, hasInvalidConstraint: Events.ValidationKeyword.hasInvalidConstraint(of: \\Self.label), keywords: Events.ValidationKeyword.keywords(of: \\Self.label)),
                            Events.EventSchema.Property(name: "count", typeName: "Int", isOptional: false, hasInvalidConstraint: Events.ValidationKeyword.hasInvalidConstraint(of: \\Self.count), keywords: Events.ValidationKeyword.keywords(of: \\Self.count)),
                            Events.EventSchema.Property(name: "tags", typeName: "[String]", isOptional: false, hasInvalidConstraint: Events.ValidationKeyword.hasInvalidConstraint(of: \\Self.tags), keywords: Events.ValidationKeyword.keywords(of: \\Self.tags), enumeration: Events.EventSchema.Enumeration(of: \\Self.tags)),
                        ])
                    }

                    private static func requireCodable(label: KeyPath<Self, some Swift.Codable>) {
                    }

                    private static func requireCodable(count: KeyPath<Self, some Swift.Codable>) {
                    }

                    private static func requireCodable(tags: KeyPath<Self, some Swift.Codable>) {
                    }

                    private static var codableRequirements: Void {
                        requireCodable(label: \\.label)
                        requireCodable(count: \\.count)
                        requireCodable(tags: \\.tags)
                    }

                    private enum CodingKeys: Swift.String, Swift.CodingKey {
                        case label
                        case count
                        case tags
                    }

                    func encode(to encoder: any Swift.Encoder) throws {
                        var container = encoder.container(keyedBy: CodingKeys.self)
                        try container.encode(self.label, forKey: .label)
                        try container.encode(self.count, forKey: .count)
                        try container.encode(self.tags, forKey: .tags)
                    }

                    init(from decoder: any Swift.Decoder) throws {
                        let container = try decoder.container(keyedBy: CodingKeys.self)
                        self.label = try container.decode(Swift.String.self, forKey: .label)
                        self.count = try container.decode(Int.self, forKey: .count)
                        self.tags = try Self.decodeValue(from: container, forKey: .tags)
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

                private enum __macro_local_15linkerSetRecordfMu_ {
                    #__eventRecord(kind: 0x65766E74, storing: Opened.self as any (Events.__DiscoverableEvent).Type)
                }

                @_silgen_name("$linkerset_kind_65766E74_key_Opened") @used nonisolated func __macro_local_18linkerSetUniqueKeyfMu_() {
                }

                nonisolated extension Opened: Swift.Encodable, Swift.Decodable, Events.__DiscoverableEvent {
                    static var name: String {
                        String(describing: Self.self)
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
            macroSpecs: ["Event": MacroSpec(type: EventMacro.self, conformances: ["Swift.Encodable", "Swift.Decodable", "__DiscoverableEvent"])],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test("A struct that already has both conformances gets their members alone")
    func noConformances() {
        assertMacroExpansion(
            """
            @Event
            struct Closed: Event, Encodable, Decodable {
            }
            """,
            expandedSource: """
                struct Closed: Event, Encodable, Decodable {
                }

                private enum __macro_local_15linkerSetRecordfMu_ {
                    #__eventRecord(kind: 0x65766E74, storing: Closed.self as any (Events.__DiscoverableEvent).Type)
                }

                @_silgen_name("$linkerset_kind_65766E74_key_Closed") @used nonisolated func __macro_local_18linkerSetUniqueKeyfMu_() {
                }

                nonisolated extension Closed {
                    static var name: String {
                        String(describing: Self.self)
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

                    #__eventRecord(kind: 0x65766E74, storing: Checkout.Started.self as any (Events.__DiscoverableEvent).Type)

                    @_silgen_name("$linkerset_kind_65766E74_key_Started") @used nonisolated static func __macro_local_18linkerSetUniqueKeyfMu_() {
                    }
                }

                nonisolated extension Checkout.Started: Events.Event, Swift.Encodable, Swift.Decodable, Events.__DiscoverableEvent {
                    static var name: String {
                        String(describing: Self.self)
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
}
