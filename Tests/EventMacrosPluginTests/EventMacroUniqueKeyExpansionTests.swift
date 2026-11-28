// The unique key @Event gives an event's record: the event's name, which LinkerSets turns into the
// symbol of a function beside the record, `$linkerset_kind_65766E74_key_<name>`, so two events of
// one name in one linked image fail to build. The function is pinned as written, since its symbol
// is what the compiler and the linker report. Each test is self-contained.

import EventMacrosPlugin
import SwiftSyntax
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacros
import SwiftSyntaxMacrosGenericTestSupport
import Testing

@Suite("@Event unique key expansions")
struct EventMacroUniqueKeyExpansionTests {
    @Test("The key is the name: argument's value alone, whatever the version, every byte but a letter or digit written as _ and two hex digits")
    func nameWithoutVersion() {
        assertMacroExpansion(
            """
            @Event(name: "checkout_started", version: 2)
            struct CheckoutStarted {
            }
            """,
            expandedSource: """
                struct CheckoutStarted {
                }

                private enum __macro_local_15linkerSetRecordfMu_ {
                    #__eventRecord(kind: 0x65766E74, storing: CheckoutStarted.self as any (Events.__DiscoverableEvent).Type)
                }

                @_silgen_name("$linkerset_kind_65766E74_key_checkout_5Fstarted") @used nonisolated func __macro_local_18linkerSetUniqueKeyfMu_() {
                }

                nonisolated extension CheckoutStarted: Events.Event, Swift.Encodable, Swift.Decodable, Events.__DiscoverableEvent {
                    static var name: String {
                        "checkout_started"
                    }

                    static var schemaVersion: Int {
                        2
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

    @Test("The key is the name's value, its escapes resolved, not the literal as written")
    func escapedName() {
        assertMacroExpansion(
            #"""
            @Event(name: "say \"hi\"")
            struct Greeted {
            }
            """#,
            expandedSource: #"""
                struct Greeted {
                }

                private enum __macro_local_15linkerSetRecordfMu_ {
                    #__eventRecord(kind: 0x65766E74, storing: Greeted.self as any (Events.__DiscoverableEvent).Type)
                }

                @_silgen_name("$linkerset_kind_65766E74_key_say_20_22hi_22") @used nonisolated func __macro_local_18linkerSetUniqueKeyfMu_() {
                }

                nonisolated extension Greeted: Events.Event, Swift.Encodable, Swift.Decodable, Events.__DiscoverableEvent {
                    static var name: String {
                        "say \"hi\""
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
                """#,
            macroSpecs: ["Event": MacroSpec(type: EventMacro.self, conformances: ["Event", "Encodable", "Decodable", "__DiscoverableEvent"])],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test("Without a name, the key is the type's name as Event's default spells it: an escaped identifier without its backticks")
    func backtickedTypeName() {
        assertMacroExpansion(
            """
            @Event
            struct `Opened` {
            }
            """,
            expandedSource: """
                struct `Opened` {
                }

                private enum __macro_local_15linkerSetRecordfMu_ {
                    #__eventRecord(kind: 0x65766E74, storing: `Opened`.self as any (Events.__DiscoverableEvent).Type)
                }

                @_silgen_name("$linkerset_kind_65766E74_key_Opened") @used nonisolated func __macro_local_18linkerSetUniqueKeyfMu_() {
                }

                nonisolated extension `Opened`: Events.Event, Swift.Encodable, Swift.Decodable, Events.__DiscoverableEvent {
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

    @Test("A private struct keeps its key: the function beside it is internal, so the linker compares it")
    func privateStruct() {
        assertMacroExpansion(
            """
            @Event
            private struct Opened {
            }
            """,
            expandedSource: """
                private struct Opened {
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

    @Test("A struct nested, at any depth, in a private type gets its record and no key, as the key's function would be local to the file")
    func inPrivateType() {
        assertMacroExpansion(
            """
            private enum Fixtures {
                enum Checkout {
                    @Event
                    struct Opened {
                    }
                }
            }
            """,
            expandedSource: """
                private enum Fixtures {
                    enum Checkout {
                        struct Opened {
                        }

                        #__eventRecord(kind: 0x65766E74, storing: Fixtures.Checkout.Opened.self as any (Events.__DiscoverableEvent).Type)
                    }
                }

                nonisolated extension Fixtures.Checkout.Opened: Events.Event, Swift.Encodable, Swift.Decodable, Events.__DiscoverableEvent {
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

    @Test("A struct in a fileprivate extension gets its record and no key")
    func inFileprivateExtension() {
        assertMacroExpansion(
            """
            fileprivate extension Shelf {
                @Event
                struct Opened {
                }
            }
            """,
            expandedSource: """
                fileprivate extension Shelf {
                    struct Opened {
                    }

                    #__eventRecord(kind: 0x65766E74, storing: Shelf.Opened.self as any (Events.__DiscoverableEvent).Type)
                }

                nonisolated extension Shelf.Opened: Events.Event, Swift.Encodable, Swift.Decodable, Events.__DiscoverableEvent {
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

    @Test("A struct in an internal or public type keeps its key, as a member of the type", arguments: ["internal", "public"])
    func inWiderType(access: String) {
        assertMacroExpansion(
            """
            \(access) enum Fixtures {
                @Event
                struct Opened {
                }
            }
            """,
            expandedSource: """
                \(access) enum Fixtures {
                    struct Opened {
                    }

                    #__eventRecord(kind: 0x65766E74, storing: Fixtures.Opened.self as any (Events.__DiscoverableEvent).Type)

                    @_silgen_name("$linkerset_kind_65766E74_key_Opened") @used nonisolated static func __macro_local_18linkerSetUniqueKeyfMu_() {
                    }
                }

                nonisolated extension Fixtures.Opened: Events.Event, Swift.Encodable, Swift.Decodable, Events.__DiscoverableEvent {
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

    @Test("A static name the struct declares itself that the Fix-It can't move, one storing no literal or declared beside another property, is an error at the member with no Fix-It", arguments: ["static var name: String { \"opened\" }", "static let name = prefix + \"opened\"", "static let name = \"opened\", screen = \"home\""])
    func nameMember(member: String) {
        assertMacroExpansion(
            """
            @Event
            struct Opened {
                \(member)
            }
            """,
            expandedSource: """
                struct Opened {
                    \(member)
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@Event reads an event's name from its name: argument, which no other event may share; give the name there, as a string literal, rather than as a member",
                    line: 3, column: 5),
            ],
            macroSpecs: ["Event": MacroSpec(type: EventMacro.self, conformances: ["Event", "Encodable", "Decodable", "__DiscoverableEvent"])],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test("A stored name property, whatever its modifiers, is the event's data, not its name: the key is still the type's name")
    func storedNameProperty() {
        assertMacroExpansion(
            """
            @Event
            struct Renamed {
                private(set) var name: String
            }
            """,
            expandedSource: """
                struct Renamed {
                    private(set) var name: String
                }

                private enum __macro_local_15linkerSetRecordfMu_ {
                    #__eventRecord(kind: 0x65766E74, storing: Renamed.self as any (Events.__DiscoverableEvent).Type)
                }

                @_silgen_name("$linkerset_kind_65766E74_key_Renamed") @used nonisolated func __macro_local_18linkerSetUniqueKeyfMu_() {
                }

                nonisolated extension Renamed: Events.Event, Swift.Encodable, Swift.Decodable, Events.__DiscoverableEvent {
                    static var name: String {
                        String(describing: Self.self)
                    }

                    static var schema: Events.EventSchema {
                        Events.EventSchema(name: Self.name, version: Self.schemaVersion, consentCategory: Self.consentCategory, properties: [
                            Events.EventSchema.Property(name: "name", typeName: "String", isOptional: false, hasInvalidConstraint: Events.ValidationKeyword.hasInvalidConstraint(of: \\Self.name), keywords: Events.ValidationKeyword.keywords(of: \\Self.name)),
                        ])
                    }

                    private static func requireCodable(name: KeyPath<Self, some Swift.Codable>) {
                    }

                    private static var codableRequirements: Void {
                        requireCodable(name: \\.name)
                    }

                    private enum CodingKeys: Swift.String, Swift.CodingKey {
                        case name
                    }

                    func encode(to encoder: any Swift.Encoder) throws {
                        var container = encoder.container(keyedBy: CodingKeys.self)
                        try container.encode(self.name, forKey: .name)
                    }

                    init(from decoder: any Swift.Decoder) throws {
                        let container = try decoder.container(keyedBy: CodingKeys.self)
                        self.name = try container.decode(String.self, forKey: .name)
                    }
                }
                """,
            macroSpecs: ["Event": MacroSpec(type: EventMacro.self, conformances: ["Event", "Encodable", "Decodable", "__DiscoverableEvent"])],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test("A static name storing a string literal gets a Fix-It that moves it into @Event(name:), first among the arguments", arguments: [
        ("@Event", "static let name = \"opened\"", "@Event(name: \"opened\")"),
        ("@Event(version: 2)", "static var name = \"opened\"", "@Event(name: \"opened\", version: 2)"),
    ])
    func nameMemberFixIt(attribute: String, member: String, fixedAttribute: String) {
        assertMacroExpansion(
            """
            \(attribute)
            struct Opened {
                \(member)
            }
            """,
            expandedSource: """
                struct Opened {
                    \(member)
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@Event reads an event's name from its name: argument, which no other event may share; give the name there, as a string literal, rather than as a member",
                    line: 3, column: 5,
                    fixIts: [FixItSpec(message: "Move the name into @Event(name:)")]),
            ],
            macroSpecs: ["Event": MacroSpec(type: EventMacro.self, conformances: ["Event", "Encodable", "Decodable", "__DiscoverableEvent"])],
            fixedSource: """
                \(fixedAttribute)
                struct Opened {
                }
                """,
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test("A static name beside a name: argument is an error with no Fix-It, as the attribute already names the event")
    func nameMemberBesideArgument() {
        assertMacroExpansion(
            """
            @Event(name: "opened")
            struct Opened {
                static let name = "launched"
            }
            """,
            expandedSource: """
                struct Opened {
                    static let name = "launched"
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@Event reads an event's name from its name: argument, which no other event may share; give the name there, as a string literal, rather than as a member",
                    line: 3, column: 5),
            ],
            macroSpecs: ["Event": MacroSpec(type: EventMacro.self, conformances: ["Event", "Encodable", "Decodable", "__DiscoverableEvent"])],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }
}
