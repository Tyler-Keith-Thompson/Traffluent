// The record @Event places in the binary for DiscoveredEvent.all, pinned. Each test is
// self-contained.
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

@Suite("@Event discovery record expansions")
struct EventMacroDiscoveryExpansionTests {
    @Test("A struct gets a LinkerSets record of the events kind beside it, holding it as a __DiscoverableEvent, which the extension conforms it to")
    func record() {
        assertMacroExpansion(
            """
            @Event(name: "signed_up")
            struct SignedUp {
            }
            """,
            expandedSource: """
                struct SignedUp {
                }

                private enum __macro_local_15linkerSetRecordfMu_ {
                    #__eventRecord(kind: 0x65766E74, storing: SignedUp.self as any (Events.__DiscoverableEvent).Type)
                }

                @_silgen_name("$linkerset_kind_65766E74_key_signed_5Fup") @used nonisolated func __macro_local_18linkerSetUniqueKeyfMu_() {
                }

                nonisolated extension SignedUp: Events.Event, Swift.Encodable, Swift.Decodable, Events.__DiscoverableEvent {
                    static var name: String {
                        "signed_up"
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

    @Test("A struct that already conforms to Event still gets its record and the __DiscoverableEvent conformance")
    func alreadyAnEvent() {
        assertMacroExpansion(
            """
            @Event
            struct Opened: Event, Codable {
            }
            """,
            expandedSource: """
                struct Opened: Event, Codable {
                }

                private enum __macro_local_15linkerSetRecordfMu_ {
                    #__eventRecord(kind: 0x65766E74, storing: Opened.self as any (Events.__DiscoverableEvent).Type)
                }

                @_silgen_name("$linkerset_kind_65766E74_key_Opened") @used nonisolated func __macro_local_18linkerSetUniqueKeyfMu_() {
                }

                nonisolated extension Opened: Events.__DiscoverableEvent {
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
            macroSpecs: ["Event": MacroSpec(type: EventMacro.self, conformances: ["__DiscoverableEvent"])],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test("A struct nested in a final class gets its record as a member of the class, naming it through the class, as a class's static members can hold one")
    func nestedInClass() {
        assertMacroExpansion(
            """
            final class Outer {
                @Event
                struct Inner {
                }
            }
            """,
            expandedSource: """
                final class Outer {
                    struct Inner {
                    }

                    #__eventRecord(kind: 0x65766E74, storing: Outer.Inner.self as any (Events.__DiscoverableEvent).Type)

                    @_silgen_name("$linkerset_kind_65766E74_key_Inner") @used nonisolated static func __macro_local_18linkerSetUniqueKeyfMu_() {
                    }
                }

                nonisolated extension Outer.Inner: Events.Event, Swift.Encodable, Swift.Decodable, Events.__DiscoverableEvent {
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

    @Test("A generic struct gets no record or __DiscoverableEvent conformance, as a record holds one concrete type, and a note at its generic clause saying to list it")
    func generic() {
        assertMacroExpansion(
            """
            @Event
            struct Tapped<Value> {
            }
            """,
            expandedSource: """
                struct Tapped<Value> {
                }

                nonisolated extension Tapped: Events.Event, Swift.Encodable, Swift.Decodable {
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
            diagnostics: [
                DiagnosticSpec(
                    message: "@Event can't give a generic struct the record DiscoveredEvent.all finds events by; list it explicitly, in SegmentStore(events:) and TrackingPlan(schemas:)",
                    line: 2, column: 14, severity: .note),
            ],
            macroSpecs: ["Event": MacroSpec(type: EventMacro.self, conformances: ["Event", "Encodable", "Decodable", "__DiscoverableEvent"])],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test("A struct nested in a generic type gets no record, at any depth, whatever kind of type it is, and a note at its name saying to list it")
    func nestedInGeneric() {
        func expansion(of enclosing: String) -> (source: String, expanded: String) {
            (
                """
                \(enclosing) Box<Value> {
                    enum Inner {
                        @Event
                        struct Opened {
                        }
                    }
                }
                """,
                """
                \(enclosing) Box<Value> {
                    enum Inner {
                        struct Opened {
                        }
                    }
                }

                nonisolated extension Box.Inner.Opened: Events.Event, Swift.Encodable, Swift.Decodable {
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
                """
            )
        }
        for enclosing in ["struct", "class", "enum", "actor"] {
            let (source, expanded) = expansion(of: enclosing)
            assertMacroExpansion(
                source,
                expandedSource: expanded,
                diagnostics: [
                    DiagnosticSpec(
                        message: "@Event can't give a struct nested in a generic type the record DiscoveredEvent.all finds events by; list it explicitly, in SegmentStore(events:) and TrackingPlan(schemas:)",
                        line: 4, column: 16, severity: .note),
                ],
                macroSpecs: ["Event": MacroSpec(type: EventMacro.self, conformances: ["Event", "Encodable", "Decodable", "__DiscoverableEvent"])],
                failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
            )
        }
    }

    @Test("A struct in an extension that shows its type is generic, by generic arguments or a where clause, gets no record and the same note", arguments: [
        ("extension Box<Int>", "Box<Int>.Opened"),
        ("extension [Int]", "[Int].Opened"),
        ("extension Box where Value == Int", "Box.Opened"),
    ])
    func inSpecializedExtension(extended: String, type: String) {
        assertMacroExpansion(
            """
            \(extended) {
                @Event
                struct Opened {
                }
            }
            """,
            expandedSource: """
                \(extended) {
                    struct Opened {
                    }
                }

                nonisolated extension \(type): Events.Event, Swift.Encodable, Swift.Decodable {
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
            diagnostics: [
                DiagnosticSpec(
                    message: "@Event can't give a struct nested in a generic type the record DiscoveredEvent.all finds events by; list it explicitly, in SegmentStore(events:) and TrackingPlan(schemas:)",
                    line: 3, column: 12, severity: .note),
            ],
            macroSpecs: ["Event": MacroSpec(type: EventMacro.self, conformances: ["Event", "Encodable", "Decodable", "__DiscoverableEvent"])],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test("A struct declared in a function gets no record or __DiscoverableEvent conformance, and the macro reports nothing, leaving the compiler's one error")
    func local() {
        assertMacroExpansion(
            """
            func open() {
                @Event
                struct Opened {
                }
            }
            """,
            // The test's expansion adds the extension the compiler refuses on a local type
            // (//Tests/CompileFailures:EventInFunction).
            expandedSource: """
                func open() {
                    struct Opened {
                    }
                }

                nonisolated extension open.Opened: Events.Event, Swift.Encodable, Swift.Decodable {
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
            diagnostics: [],
            macroSpecs: ["Event": MacroSpec(type: EventMacro.self, conformances: ["Event", "Encodable", "Decodable", "__DiscoverableEvent"])],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }
}
