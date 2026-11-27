import AutomaticControlTracking
import DiscoveryFixtures
import EventMacros
import Events
import LifecycleTracking
import Sessions
import SwiftUITracking
import Testing

// This target's binary holds the events of its three files, DiscoveryFixtures' two and the
// library's own of the modules it links, and no two of one name.

@Event(name: "discovery_signed_up")
struct DiscoverySignedUp {
    var plan: String
}

enum DiscoveryScreens {
    @Event(name: "discovery_screen_shown", version: 3)
    struct Shown {
        var title: String
    }
}

@Event(name: "discovery_wrapped")
struct DiscoveryWrapped<Value: Codable & Sendable> {
    var value: Value
}

/// An event that conforms by hand, without `@Event`.
struct DiscoveryHandWritten: Event, Codable {
    static let name = "discovery_hand_written"
    static let schema = EventSchema(name: name, version: schemaVersion, consentCategory: consentCategory, properties: [])
}

/// An event conforming by hand whose record, in the events' section, is of another kind.
struct DiscoveryOtherKind: Event, Codable {
    static let name = "discovery_other_kind"
    static let schema = EventSchema(name: name, version: schemaVersion, consentCategory: consentCategory, properties: [])
}

// A record that would load DiscoveryOtherKind but carries a kind other than __EventDiscovery.kind,
// as another tool's records in the same section might, so the reader must skip it.
extension DiscoveryOtherKind {
    #if objectFormat(MachO)
        @section("__DATA_CONST,__trfl_events")
    #elseif objectFormat(ELF)
        @section("trfl_events")
    #endif
    @used
    private nonisolated static let otherKindRecord: __EventDiscovery.Record = (0x7465_7374, 0, { outValue, type, _, _ in __EventDiscovery.load(DiscoveryOtherKind.self, schema: DiscoveryOtherKind.schema, into: outValue, ofType: type) }, 0, 0)
}

// A second record of DiscoverySignedUp, beside the one @Event gave it, as a type whose record's
// object file is linked twice would have.
extension DiscoverySignedUp {
    #if objectFormat(MachO)
        @section("__DATA_CONST,__trfl_events")
    #elseif objectFormat(ELF)
        @section("trfl_events")
    #endif
    @used
    private nonisolated static let repeatedRecord: __EventDiscovery.Record = (0x6576_6E74, 0, { outValue, type, _, _ in __EventDiscovery.load(DiscoverySignedUp.self, schema: DiscoverySignedUp.schema, into: outValue, ofType: type) }, 0, 0)
}

@Suite("DiscoveredEvent")
struct DiscoveredEventTests {
    @Test("all lists every @Event of every module the program links and the library's own, by the UTF-8 bytes of their names")
    func everyEvent() {
        let expected = [
            "ApplicationBackgrounded",
            "ApplicationInstalled",
            "ApplicationOpened",
            "ApplicationTerminated",
            "ApplicationUpdated",
            "ControlActivated",
            "ScreenViewed",
            "SessionEnded",
            "SessionStarted",
            "discovery_item_stored",
            "discovery_plan_viewed",
            "discovery_screen_shown",
            "discovery_signed_up",
            "fixture_checkout_started",
            "fixture_opened",
        ]

        let actual = DiscoveredEvent.all.map { $0.type.name }

        #expect(actual == expected)
    }

    @Test("Each discovered event carries its type's schema, its version included")
    func schemas() {
        let expected = [
            ApplicationBackgrounded.schema,
            ApplicationInstalled.schema,
            ApplicationOpened.schema,
            ApplicationTerminated.schema,
            ApplicationUpdated.schema,
            ControlActivated.schema,
            ScreenViewed.schema,
            SessionEnded.schema,
            SessionStarted.schema,
            DiscoveryItemStored.schema,
            DiscoveryPlanViewed.schema,
            DiscoveryScreens.Shown.schema,
            DiscoverySignedUp.schema,
            EventSchema(name: "fixture_checkout_started", version: 1, consentCategory: .analytics, properties: [
                EventSchema.Property(name: "cartSize", typeName: "Int", isOptional: false),
            ]),
            EventSchema(name: "fixture_opened", version: 2, consentCategory: .analytics, properties: [
                EventSchema.Property(name: "screen", typeName: "String", isOptional: false),
            ]),
        ]

        let actual = DiscoveredEvent.all.map(\.schema)

        #expect(actual == expected)
    }

    @Test("Each discovered event's type is the type that declared it")
    func types() {
        let expected = [
            String(reflecting: DiscoverySignedUp.self),
            String(reflecting: FixtureOpened.self),
            String(reflecting: SessionStarted.self),
        ]

        let actual = DiscoveredEvent.all.map { String(reflecting: $0.type) }

        #expect(expected.allSatisfy(actual.contains))
    }

    @Test("A generic @Event and a hand-written conformance aren't discovered")
    func notDiscovered() {
        let undiscovered = [DiscoveryWrapped<Int>.name, DiscoveryHandWritten.name]

        let actual = DiscoveredEvent.all.map { $0.type.name }

        #expect(undiscovered.allSatisfy { !actual.contains($0) })
    }

    @Test("A type with two records is listed once")
    func repeatedRecordListedOnce() {
        let expectedCount = 1

        let actual = DiscoveredEvent.all.filter { ObjectIdentifier($0.type) == ObjectIdentifier(DiscoverySignedUp.self) }.count

        #expect(actual == expectedCount)
    }

    @Test("A record of another kind in the events' section is skipped")
    func otherKindSkipped() {
        let skipped = DiscoveryOtherKind.name

        let actual = DiscoveredEvent.all.map { $0.type.name }

        #expect(!actual.contains(skipped))
    }

    @Test("A record's loader writes the event only for the reader asking for this module's DiscoveredEvent")
    func loaderChecksTheType() {
        func load(asking expectedType: Any.Type) -> DiscoveredEvent? {
            withUnsafeTemporaryAllocation(of: DiscoveredEvent.self, capacity: 1) { buffer in
                withUnsafePointer(to: expectedType) { expectedType in
                    guard let outValue = buffer.baseAddress,
                        __EventDiscovery.load(DiscoverySignedUp.self, schema: DiscoverySignedUp.schema, into: outValue, ofType: expectedType)
                    else { return nil }
                    return outValue.move()
                }
            }
        }
        let expectedSchema = DiscoverySignedUp.schema

        let actual = load(asking: DiscoveredEvent.self)
        let refused = load(asking: Int.self)

        #expect(actual?.schema == expectedSchema)
        #expect(actual.map { ObjectIdentifier($0.type) } == ObjectIdentifier(DiscoverySignedUp.self))
        #expect(refused == nil)
    }
}
