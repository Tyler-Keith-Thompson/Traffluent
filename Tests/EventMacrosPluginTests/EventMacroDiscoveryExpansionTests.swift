// The record @Event places in the binary for DiscoveredEvent.all, pinned. Each test is
// self-contained.
//
// A test whose expected source holds a discovery record sits under
// `#if canImport(SwiftSyntax602)`: swift-syntax 600's and 601's assertMacroExpansion drop the
// `#if objectFormat(...)` lines of a peer's expansion, so the record can't be pinned there. The
// others run on every swift-syntax the plugin accepts.

import EventMacrosPlugin
import SwiftSyntax
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacros
import SwiftSyntaxMacrosGenericTestSupport
import Testing

@Suite("@Event discovery record expansions")
struct EventMacroDiscoveryExpansionTests {
    #if canImport(SwiftSyntax602)
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

                #if objectFormat(MachO)
                @section("__DATA_CONST,__linker_sets") @used private let __macro_local_15linkerSetRecordfMu_: LinkerSetsRuntime.LinkerSetRecord.Literal = (0x65766E74, 0, { outValue, type, _, _ in
                        LinkerSetsRuntime.LinkerSetRecord.__store(SignedUp.self as any (Events.__DiscoverableEvent).Type, into: outValue, ifAsked: type)
                    }, 0, 0)
                #elseif objectFormat(ELF) && _pointerBitWidth(_64)
                @section(".note.linker_sets") @used private let __macro_local_15linkerSetRecordfMu_: LinkerSetsRuntime.LinkerSetRecord.Note = (11, 32, 1, (76, 105, 110, 107, 101, 114, 83, 101, 116, 115, 0, 0), (0x65766E74, 0, { outValue, type, _, _ in
                            LinkerSetsRuntime.LinkerSetRecord.__store(SignedUp.self as any (Events.__DiscoverableEvent).Type, into: outValue, ifAsked: type)
                        }, 0, 0))
                #elseif objectFormat(ELF) && _pointerBitWidth(_32)
                @section(".note.linker_sets") @used private let __macro_local_15linkerSetRecordfMu_: LinkerSetsRuntime.LinkerSetRecord.Note = (11, 20, 1, (76, 105, 110, 107, 101, 114, 83, 101, 116, 115, 0, 0), (0x65766E74, 0, { outValue, type, _, _ in
                            LinkerSetsRuntime.LinkerSetRecord.__store(SignedUp.self as any (Events.__DiscoverableEvent).Type, into: outValue, ifAsked: type)
                        }, 0, 0))
                #elseif objectFormat(Wasm)
                @section("linker_sets") @used private let __macro_local_15linkerSetRecordfMu_: LinkerSetsRuntime.LinkerSetRecord.Literal = (0x65766E74, 0, { outValue, type, _, _ in
                        LinkerSetsRuntime.LinkerSetRecord.__store(SignedUp.self as any (Events.__DiscoverableEvent).Type, into: outValue, ifAsked: type)
                    }, 0, 0)
                #elseif objectFormat(COFF)
                @section(".lnkset$M") @used private let __macro_local_15linkerSetRecordfMu_: LinkerSetsRuntime.LinkerSetRecord.Literal = (0x65766E74, 0, { outValue, type, _, _ in
                        LinkerSetsRuntime.LinkerSetRecord.__store(SignedUp.self as any (Events.__DiscoverableEvent).Type, into: outValue, ifAsked: type)
                    }, 0, 0)
                #endif

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
    #endif

    #if canImport(SwiftSyntax602)
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

                #if objectFormat(MachO)
                @section("__DATA_CONST,__linker_sets") @used private let __macro_local_15linkerSetRecordfMu_: LinkerSetsRuntime.LinkerSetRecord.Literal = (0x65766E74, 0, { outValue, type, _, _ in
                        LinkerSetsRuntime.LinkerSetRecord.__store(Opened.self as any (Events.__DiscoverableEvent).Type, into: outValue, ifAsked: type)
                    }, 0, 0)
                #elseif objectFormat(ELF) && _pointerBitWidth(_64)
                @section(".note.linker_sets") @used private let __macro_local_15linkerSetRecordfMu_: LinkerSetsRuntime.LinkerSetRecord.Note = (11, 32, 1, (76, 105, 110, 107, 101, 114, 83, 101, 116, 115, 0, 0), (0x65766E74, 0, { outValue, type, _, _ in
                            LinkerSetsRuntime.LinkerSetRecord.__store(Opened.self as any (Events.__DiscoverableEvent).Type, into: outValue, ifAsked: type)
                        }, 0, 0))
                #elseif objectFormat(ELF) && _pointerBitWidth(_32)
                @section(".note.linker_sets") @used private let __macro_local_15linkerSetRecordfMu_: LinkerSetsRuntime.LinkerSetRecord.Note = (11, 20, 1, (76, 105, 110, 107, 101, 114, 83, 101, 116, 115, 0, 0), (0x65766E74, 0, { outValue, type, _, _ in
                            LinkerSetsRuntime.LinkerSetRecord.__store(Opened.self as any (Events.__DiscoverableEvent).Type, into: outValue, ifAsked: type)
                        }, 0, 0))
                #elseif objectFormat(Wasm)
                @section("linker_sets") @used private let __macro_local_15linkerSetRecordfMu_: LinkerSetsRuntime.LinkerSetRecord.Literal = (0x65766E74, 0, { outValue, type, _, _ in
                        LinkerSetsRuntime.LinkerSetRecord.__store(Opened.self as any (Events.__DiscoverableEvent).Type, into: outValue, ifAsked: type)
                    }, 0, 0)
                #elseif objectFormat(COFF)
                @section(".lnkset$M") @used private let __macro_local_15linkerSetRecordfMu_: LinkerSetsRuntime.LinkerSetRecord.Literal = (0x65766E74, 0, { outValue, type, _, _ in
                        LinkerSetsRuntime.LinkerSetRecord.__store(Opened.self as any (Events.__DiscoverableEvent).Type, into: outValue, ifAsked: type)
                    }, 0, 0)
                #endif

                nonisolated extension Opened: Events.__DiscoverableEvent {
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
    #endif

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
