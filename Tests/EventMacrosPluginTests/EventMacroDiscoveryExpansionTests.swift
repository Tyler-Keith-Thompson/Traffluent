// The record @Event places in the binary for DiscoveredEvent.all, pinned. Each test is
// self-contained.

import EventMacrosPlugin
import SwiftSyntax
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacros
import SwiftSyntaxMacrosGenericTestSupport
import Testing

@Suite("@Event discovery record expansions")
struct EventMacroDiscoveryExpansionTests {
    @Test("A struct's record goes in the event section of Mach-O and ELF, kept by @used, and loads the struct with its schema")
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

                extension SignedUp: Events.Event, Swift.Encodable, Swift.Decodable {
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

                extension SignedUp {
                    #if objectFormat(MachO)
                    @section("__DATA_CONST,__trfl_events")
                    #elseif objectFormat(ELF)
                    @section("trfl_events")
                    #endif
                    @used
                    private nonisolated static let __discoveryRecord: Events.__EventDiscovery.Record = (0x6576_6E74, 0, { outValue, type, _, _ in
                            Events.__EventDiscovery.load(SignedUp.self, schema: SignedUp.schema, into: outValue, ofType: type)
                        }, 0, 0)
                }
                """,
            macroSpecs: ["Event": MacroSpec(type: EventMacro.self, conformances: ["Event", "Encodable", "Decodable"])],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test("A struct that already conforms to Event still gets its record")
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

                extension Opened {
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

                extension Opened {
                    #if objectFormat(MachO)
                    @section("__DATA_CONST,__trfl_events")
                    #elseif objectFormat(ELF)
                    @section("trfl_events")
                    #endif
                    @used
                    private nonisolated static let __discoveryRecord: Events.__EventDiscovery.Record = (0x6576_6E74, 0, { outValue, type, _, _ in
                            Events.__EventDiscovery.load(Opened.self, schema: Opened.schema, into: outValue, ofType: type)
                        }, 0, 0)
                }
                """,
            macroSpecs: ["Event": MacroSpec(type: EventMacro.self, conformances: [])],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test("A generic struct gets no record, as a generic type can't hold a static stored property, and a note at its generic clause saying to list it")
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

                extension Tapped: Events.Event, Swift.Encodable, Swift.Decodable {
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
            macroSpecs: ["Event": MacroSpec(type: EventMacro.self, conformances: ["Event", "Encodable", "Decodable"])],
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

                extension Box.Inner.Opened: Events.Event, Swift.Encodable, Swift.Decodable {
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
                macroSpecs: ["Event": MacroSpec(type: EventMacro.self, conformances: ["Event", "Encodable", "Decodable"])],
                failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
            )
        }
    }
}
